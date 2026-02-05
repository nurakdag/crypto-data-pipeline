##############################################################################
# S3 Resources
#
# Her iki bucket de Terraform tarafindan olusturuluyor.
# 1. Raw bucket     -> Airflow'un JSON yazdigi bucket
# 2. Processed bucket -> Lambda'nin Parquet yazdigi bucket
#
# Iki bucket'a da ayni guvenlik standartlari uygulanir:
#   - Versioning acik
#   - Public access engellenm
#   - Lifecycle rule ile maliyet kontrolu
##############################################################################

# ===================================================================
#  RAW BUCKET
# ===================================================================

resource "aws_s3_bucket" "raw" {
  bucket = "${var.project_name}-raw-${var.environment}"

  tags = {
    Name = "${var.project_name}-raw-${var.environment}"
    Tier = "raw"
  }
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Raw data immutable olmali, ama yine de eski veriyi ucuz storage'a tasi
resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    id     = "archive-old-raw-data"
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

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ===================================================================
#  PROCESSED BUCKET
# ===================================================================

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

resource "aws_s3_bucket_lifecycle_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id

  rule {
    id     = "archive-old-processed-data"
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

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket = aws_s3_bucket.processed.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
