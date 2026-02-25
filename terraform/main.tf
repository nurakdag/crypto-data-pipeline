##############################################################################
# Terraform Configuration
#
# Defines provider and backend only.
# Resource definitions live in their respective files: s3.tf, iam.tf, lambda.tf, etc.
##############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # -----------------------------------------------------------------
  # Backend: local for development. Switch to S3 backend for production.
  #
  # Production example:
  #
  # backend "s3" {
  #   bucket         = "my-terraform-state-bucket"
  #   key            = "crypto-pipeline/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
  # -----------------------------------------------------------------
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "crypto-data-pipeline"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
