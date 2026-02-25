##############################################################################
# Variables
#
# All input variables are declared here.
# Values are supplied via terraform.tfvars or the CLI.
#
# Usage:
#   terraform plan -var="environment=prod"
#   or create a terraform.tfvars file
##############################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment: dev, staging, or prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name — used as a prefix in all resource names"
  type        = string
  default     = "crypto-data-pipeline"
}

variable "raw_prefix" {
  description = "S3 prefix that triggers the Lambda function (files under raw/)"
  type        = string
  default     = "raw/"
}

variable "raw_suffix" {
  description = "S3 key suffix that triggers the Lambda function"
  type        = string
  default     = ".json"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 120
}

variable "lambda_memory" {
  description = "Lambda function memory in MB (512 MB is sufficient for Parquet conversion)"
  type        = number
  default     = 512
}

variable "alert_email" {
  description = "Email address that receives pipeline alarm notifications"
  type        = string
  default     = "admin@example.com"
}
