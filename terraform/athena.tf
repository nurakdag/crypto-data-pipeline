##############################################################################
# AWS Athena - Serverless SQL Query Engine
#
# How Athena works:
#   1. Reads the table definition from the Glue Data Catalog
#   2. Queries Parquet files directly in S3 (data is never moved)
#   3. Writes query results to a dedicated S3 bucket (CSV format)
#
# Why Athena instead of Redshift?
#   - Redshift: you run a cluster and pay ~$0.25+/hour even when idle
#     (~$180+/month just to keep it running)
#   - Athena: serverless, you pay only for data scanned
#     1 TB queried with Parquet ≈ $5 (our dataset is tiny — cents)
#
# Cost control:
#   - bytes_scanned_cutoff_per_query limits scanned data per query
#   - If a runaway SELECT * exceeds the limit, the query is cancelled
##############################################################################

# -----------------------------------------------------------------
# Athena Query Results Bucket
#
# Athena writes every query result to S3 (CSV). This bucket is mandatory.
#
# 7-day lifecycle rule: query results are temporary and can be
# discarded quickly to keep storage costs near zero.
# -----------------------------------------------------------------
resource "aws_s3_bucket" "athena_results" {
  bucket = "${var.project_name}-athena-results-${var.environment}"

  tags = {
    Name = "${var.project_name}-athena-results-${var.environment}"
    Tier = "athena-results"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "cleanup-old-query-results"
    status = "Enabled"

    filter {} # Apply to all objects

    expiration {
      days = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------
# Athena Workgroup
#
# A workgroup provides isolation and cost control within Athena.
#
# enforce_workgroup_configuration = true:
#   Users cannot override the output location.
#   Results always go to the bucket we define here.
#   This prevents accidental (or malicious) data exfiltration.
#
# bytes_scanned_cutoff_per_query:
#   Queries that exceed this limit are automatically cancelled.
#   Guards against accidentally scanning billions of rows.
#   1 GB ≈ $0.005 — a safe and generous limit for this workload.
# -----------------------------------------------------------------
resource "aws_athena_workgroup" "crypto_workgroup" {
  name        = "${var.project_name}-workgroup-${var.environment}"
  description = "Crypto data pipeline Athena workgroup (${var.environment})"

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    bytes_scanned_cutoff_per_query = 1073741824 # 1GB

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = {
    Name = "${var.project_name}-workgroup-${var.environment}"
  }
}
