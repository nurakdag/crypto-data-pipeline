##############################################################################
# S3 Resources
#
# 1. Raw bucket     -> Zaten var, data source olarak referans aliyoruz
# 2. Processed bucket -> Terraform olusturacak (Parquet dosyalari icin)
##############################################################################

# -----------------------------------------------------------------
# Raw Bucket (mevcut)
#
# Bu bucket'i Terraform OLUSTURMUYOR.
# data source ile sadece ARN'ini aliyoruz,
# event notification ve IAM policy'de kullanmak icin.
#
# DIKKAT: Eger bu bucket yoksa terraform plan hata verir.
# Once bucket'in var oldugundan emin ol:
#   aws s3 ls s3://crypto-raw-dev-20260131
# -----------------------------------------------------------------
data "aws_s3_bucket" "raw" {
  bucket = var.raw_bucket_name
}

# -----------------------------------------------------------------
# Processed Bucket (yeni)
#
# Lambda'nin Parquet dosyalarini yazacagi bucket.
# Versioning acik: yanlislikla uzerine yazarsan geri donebilirsin.
# -----------------------------------------------------------------
resource "aws_s3_bucket" "processed" {
  bucket = "${var.project_name}-processed-${var.environment}"

  tags = {
    Name = "${var.project_name}-processed-${var.environment}"
    Tier = "processed"
  }
}

resource "aws_s3_bucket_versioning" "processed" {
  bucket = aws_s3_bucket.processed.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle rule: 90 gun sonra IA'ya tasi, 365 gun sonra Glacier'a
resource "aws_s3_bucket_lifecycle_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id

  rule {
    id     = "archive-old-data"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }
}

# Public access engelle - ZORUNLU
resource "aws_s3_bucket_public_access_block" "processed" {
  bucket = aws_s3_bucket.processed.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
