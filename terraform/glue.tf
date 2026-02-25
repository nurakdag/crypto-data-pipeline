##############################################################################
# AWS Glue - Data Catalog Database & Table (Partition Projection)
#
# We do NOT use a Glue Crawler. Why?
#   1. Crawler creation may be restricted in the AWS account
#   2. Crawlers cost money (~$0.44/DPU-hour)
#   3. We already know the schema — there is nothing to discover
#
# Instead:
#   - The Glue Catalog Table is defined directly in Terraform
#   - Athena Partition Projection resolves new partitions INSTANTLY
#   - Cost: $0
#
# What is Partition Projection?
#   We tell Athena: "the date partition ranges from 2026-01-01 to NOW,
#   and the hour partition is an integer between 00 and 23."
#   Athena computes new partitions from metadata without hitting S3.
#   Result:
#   - New partitions (new day/hour) are queryable immediately
#   - No need to run MSCK REPAIR TABLE
#   - No need to run a Crawler
##############################################################################

# -----------------------------------------------------------------
# Lake Formation Settings
#
# New AWS accounts have Lake Formation enabled by default.
# Setting IAM_ALLOWED_PRINCIPALS tells Lake Formation:
#   "grant Data Catalog access to anyone with the right IAM permission."
# -----------------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_lakeformation_data_lake_settings" "default" {
  admins = [
    data.aws_caller_identity.current.arn,
  ]

  create_database_default_permissions {
    permissions = ["ALL"]
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }

  create_table_default_permissions {
    permissions = ["ALL"]
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }
}

# -----------------------------------------------------------------
# Glue Catalog Database
# -----------------------------------------------------------------
resource "aws_glue_catalog_database" "crypto_db" {
  name = "${replace(var.project_name, "-", "_")}_${var.environment}"

  description = "Crypto data pipeline - processed Parquet tables (${var.environment})"

  depends_on = [aws_lakeformation_data_lake_settings.default]
}

# -----------------------------------------------------------------
# Glue Catalog Table - coins_markets
#
# Columns: fields returned by the CoinGecko API
# Partition keys: Hive-style key=value pairs embedded in the S3 path
#
# Example S3 path:
#   processed/source=coingecko/dataset=coins_markets/date=2026-02-05/hour=12/data_*.parquet
#
# Partition Projection settings:
#   - source: enum (coingecko) — additional sources can be added later
#   - dataset: enum (coins_markets) — additional datasets can be added later
#   - date: from 2026-01-01 to NOW, daily interval
#   - hour: 0–23, zero-padded to 2 digits (00, 01, ..., 23)
# -----------------------------------------------------------------
resource "aws_glue_catalog_table" "coins_markets" {
  name          = "coins_markets"
  database_name = aws_glue_catalog_database.crypto_db.name
  description   = "CoinGecko cryptocurrency market data (Parquet)"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"      = "parquet"
    "parquet.compression" = "SNAPPY"
    # --- Partition Projection ---
    "projection.enabled"            = "true"
    "projection.source.type"        = "enum"
    "projection.source.values"      = "coingecko"
    "projection.dataset.type"       = "enum"
    "projection.dataset.values"     = "coins_markets"
    "projection.date.type"          = "date"
    "projection.date.format"        = "yyyy-MM-dd"
    "projection.date.range"         = "2026-01-01,NOW"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "projection.hour.type"          = "integer"
    "projection.hour.range"         = "0,23"
    "projection.hour.digits"        = "2"
    "storage.location.template"     = "s3://${aws_s3_bucket.processed.id}/processed/source=$${source}/dataset=$${dataset}/date=$${date}/hour=$${hour}"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.processed.id}/processed/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    # Data columns (partition keys are declared separately below)
    columns {
      name = "id"
      type = "string"
    }
    columns {
      name = "symbol"
      type = "string"
    }
    columns {
      name = "name"
      type = "string"
    }
    columns {
      name = "current_price"
      type = "double"
    }
    columns {
      name = "market_cap"
      type = "double"
    }
    columns {
      name = "total_volume"
      type = "double"
    }
    columns {
      name = "processed_at"
      type = "string"
    }
  }

  # Partition keys (Hive-style key=value pairs from the S3 path)
  partition_keys {
    name = "source"
    type = "string"
  }
  partition_keys {
    name = "dataset"
    type = "string"
  }
  partition_keys {
    name = "date"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }
}
