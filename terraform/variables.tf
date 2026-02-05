##############################################################################
# Variables
#
# Tum degiskenler burada tanimlanir.
# Degerler terraform.tfvars veya CLI'dan verilir.
#
# Kullanim:
#   terraform plan -var="environment=prod"
#   veya terraform.tfvars dosyasi olustur
##############################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Ortam adi: dev, staging, prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment 'dev', 'staging' veya 'prod' olmali."
  }
}

variable "project_name" {
  description = "Proje adi - kaynak isimlendirmede kullanilir"
  type        = string
  default     = "crypto-data-pipeline"
}

variable "raw_prefix" {
  description = "Lambda'yi tetikleyecek S3 prefix (raw/ altindaki dosyalar)"
  type        = string
  default     = "raw/"
}

variable "raw_suffix" {
  description = "Lambda'yi tetikleyecek dosya uzantisi"
  type        = string
  default     = ".json"
}

variable "lambda_timeout" {
  description = "Lambda timeout suresi (saniye)"
  type        = number
  default     = 120
}

variable "lambda_memory" {
  description = "Lambda memory (MB) - Parquet donusumu icin 512MB yeterli"
  type        = number
  default     = 512
}
