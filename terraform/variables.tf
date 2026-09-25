variable "project" {
  type    = string
  default = "payments-recon"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "snowflake_organization_name" { type = string }
variable "snowflake_account_name" { type = string }

variable "snowflake_admin_user" {
  type        = string
  description = "Your own Snowflake user (with ACCOUNTADMIN), authenticated by key pair."
}

variable "snowflake_admin_private_key_path" {
  type    = string
  default = "../keys/admin_key.p8"
}

variable "service_user_rsa_public_key" {
  type        = string
  description = "Body of keys/svc_key.pub without the BEGIN/END lines (make keys prints it)."
}

variable "snowpipe_sqs_arn" {
  type        = string
  default     = ""
  description = "Second apply only: notification_channel from SHOW PIPES in Snowflake."
}
