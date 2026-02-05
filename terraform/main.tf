##############################################################################
# Terraform Configuration
#
# Bu dosya sadece provider ve backend tanimlar.
# Kaynak tanimlari ilgili dosyalarda: s3.tf, iam.tf, lambda.tf, vs.
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
  # Backend: Simdilik local. Production'da S3 backend kullanilmali.
  #
  # Gercek projede su sekilde olur:
  #
  # backend "s3" {
  #   bucket         = "my-terraform-state-bucket"
  #   key            = "crypto-pipeline/terraform.tfstate"
  #   region         = "eu-central-1"
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
