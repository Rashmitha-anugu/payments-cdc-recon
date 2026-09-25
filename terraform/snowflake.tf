resource "snowflake_warehouse" "wh" {
  name                = "PAYMENTS_WH"
  warehouse_size      = "XSMALL"
  auto_suspend        = 60
  initially_suspended = true
  comment             = "Payments recon: ingestion + dbt"
}

resource "snowflake_database" "db" {
  name = "PAYMENTS"
}

resource "snowflake_storage_integration" "landing" {
  name                      = "PAYMENTS_S3_INT"
  type                      = "EXTERNAL_STAGE"
  storage_provider          = "S3"
  enabled                   = true
  storage_aws_role_arn      = local.snowflake_role_arn
  storage_allowed_locations = ["s3://${aws_s3_bucket.landing.bucket}/"]
}

# ---------------------------------------------------------------- RBAC

resource "snowflake_account_role" "transformer" {
  name    = "PAYMENTS_TRANSFORMER"
  comment = "Owns RAW objects and dbt-built schemas"
}

resource "snowflake_grant_account_role" "transformer_to_sysadmin" {
  role_name        = snowflake_account_role.transformer.name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_privileges_to_account_role" "warehouse" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE", "OPERATE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.wh.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "database" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE", "CREATE SCHEMA"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.db.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "integration" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "INTEGRATION"
    object_name = snowflake_storage_integration.landing.name
  }
}

# ---------------------------------------------------------------- service user (dbt + Airflow)

resource "snowflake_service_user" "pipeline" {
  name              = "PAYMENTS_SVC"
  default_warehouse = snowflake_warehouse.wh.name
  default_role      = snowflake_account_role.transformer.name
  rsa_public_key    = var.service_user_rsa_public_key
  comment           = "Key-pair auth only; used by dbt and Airflow"
}

resource "snowflake_grant_account_role" "transformer_to_svc" {
  role_name = snowflake_account_role.transformer.name
  user_name = snowflake_service_user.pipeline.name
}
