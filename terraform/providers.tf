provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { project = var.project, managed_by = "terraform" }
  }
}

provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_admin_user
  role              = "ACCOUNTADMIN" # storage integrations require it
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = file(var.snowflake_admin_private_key_path)

  preview_features_enabled = ["snowflake_storage_integration_resource"]
}
