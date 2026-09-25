data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name         = "${var.project}-landing-${random_id.suffix.hex}"
  snowflake_role_name = "${var.project}-snowflake-reader"
  # Built as a string so the integration and the role can be created in one apply.
  snowflake_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.snowflake_role_name}"
}

# ---------------------------------------------------------------- landing bucket

resource "aws_s3_bucket" "landing" {
  bucket        = local.bucket_name
  force_destroy = true # portfolio project: lets `terraform destroy` clean up fully
}

resource "aws_s3_bucket_public_access_block" "landing" {
  bucket                  = aws_s3_bucket.landing.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "landing" {
  bucket = aws_s3_bucket.landing.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "landing" {
  bucket = aws_s3_bucket.landing.id
  rule {
    id     = "age-out-raw-cdc"
    status = "Enabled"
    filter {
      prefix = "cdc/"
    }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    expiration {
      days = 180
    }
  }
}

# Snowpipe auto-ingest: S3 -> Snowflake-managed SQS queue. Needs the pipe to exist first,
# so it's skipped on the first apply (see README "two-pass bootstrap").
resource "aws_s3_bucket_notification" "snowpipe" {
  count  = var.snowpipe_sqs_arn == "" ? 0 : 1
  bucket = aws_s3_bucket.landing.id

  queue {
    id            = "cdc"
    queue_arn     = var.snowpipe_sqs_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "cdc/"
  }

  queue {
    id            = "settlements"
    queue_arn     = var.snowpipe_sqs_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "settlements/"
  }
}

# ---------------------------------------------------------------- writer (local pipeline)

# Local docker containers need static keys. On AWS you'd use an instance/IRSA role instead.
resource "aws_iam_user" "pipeline" {
  name = "${var.project}-pipeline"
}

resource "aws_iam_access_key" "pipeline" {
  user = aws_iam_user.pipeline.name
}

data "aws_iam_policy_document" "pipeline_write" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.landing.arn]
  }
  statement {
    actions = [
      "s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.landing.arn}/*"]
  }
}

resource "aws_iam_user_policy" "pipeline_write" {
  name   = "landing-write"
  user   = aws_iam_user.pipeline.name
  policy = data.aws_iam_policy_document.pipeline_write.json
}

# ---------------------------------------------------------------- reader (Snowflake)

data "aws_iam_policy_document" "snowflake_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [snowflake_storage_integration.landing.storage_aws_iam_user_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [snowflake_storage_integration.landing.storage_aws_external_id]
    }
  }
}

resource "aws_iam_role" "snowflake_reader" {
  name               = local.snowflake_role_name
  assume_role_policy = data.aws_iam_policy_document.snowflake_trust.json
}

data "aws_iam_policy_document" "snowflake_read" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.landing.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.landing.arn}/*"]
  }
}

resource "aws_iam_role_policy" "snowflake_read" {
  name   = "landing-read"
  role   = aws_iam_role.snowflake_reader.id
  policy = data.aws_iam_policy_document.snowflake_read.json
}
