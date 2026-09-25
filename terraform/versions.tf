terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    snowflake = {
      # The Snowflake provider has had breaking changes between majors.
      # This config targets the 1.x resource names; check the upgrade guide before bumping.
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
