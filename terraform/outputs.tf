output "s3_bucket" {
  value = aws_s3_bucket.landing.bucket
}

output "pipeline_access_key_id" {
  value = aws_iam_access_key.pipeline.id
}

output "pipeline_secret_access_key" {
  value     = aws_iam_access_key.pipeline.secret
  sensitive = true
}

output "next_step" {
  value = var.snowpipe_sqs_arn == "" ? "Run `make snowflake-setup`, then set snowpipe_sqs_arn from SHOW PIPES and apply again." : "Snowpipe notifications wired."
}
