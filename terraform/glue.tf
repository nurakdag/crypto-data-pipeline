##############################################################################
# AWS Glue - Data Catalog Database & Table (Partition Projection)
#
# Crawler KULLANMIYORUZ. Neden?
#   1. AWS hesabinda Crawler olusturma kisitli (Account denied access)
#   2. Crawler maliyet (~$0.44/DPU-saat)
#   3. Biz semayi zaten biliyoruz, kesfetmeye gerek yok
#
# Bunun yerine:
#   - Glue Catalog Table'i Terraform ile tanimliyoruz
#   - Athena Partition Projection ile yeni partition'lar ANINDA bulunuyor
#   - Maliyet: $0
#
# Partition Projection nedir?
#   Athena'ya diyoruz ki: "date partition'i 2026-01-01'den bugune kadar,
#   hour partition'i 00 ile 23 arasi olacak." Athena yeni partition'lari
#   S3'e bakmadan, metadata'dan hesaplar. Sonuc:
#   - Yeni partition (yeni gun/saat) eklediginde ANINDA sorgulanabilir
#   - MSCK REPAIR TABLE calistirmaya gerek yok
#   - Crawler calistirmaya gerek yok
##############################################################################

# -----------------------------------------------------------------
# Lake Formation Ayarlari
#
# Yeni AWS hesaplarinda Lake Formation varsayilan olarak acik gelir.
# IAM_ALLOWED_PRINCIPALS ayari Lake Formation'a:
#   "IAM yetkisi olan herkese Data Catalog erisimi ver" der.
# -----------------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_lakeformation_data_lake_settings" "default" {
  admins = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/terraform-deployer",
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

  description = "Crypto data pipeline - processed Parquet tablolari (${var.environment})"

  depends_on = [aws_lakeformation_data_lake_settings.default]
}

# -----------------------------------------------------------------
# Glue Catalog Table - coins_markets
#
# Kolonlar: CoinGecko API'den gelen alanlar
# Partition key'ler: S3 path'teki Hive-style key=value ciftleri
#
# S3 path ornegi:
#   processed/source=coingecko/dataset=coins_markets/date=2026-02-05/hour=12/data_*.parquet
#
# Partition Projection ayarlari:
#   - source: enum (coingecko) - ileride baska kaynaklar eklenebilir
#   - dataset: enum (coins_markets) - ileride baska datasetler eklenebilir
#   - date: 2026-01-01'den bugune, gunluk aralik
#   - hour: 0-23, 2 haneli (00, 01, ..., 23)
# -----------------------------------------------------------------
resource "aws_glue_catalog_table" "coins_markets" {
  name          = "coins_markets"
  database_name = aws_glue_catalog_database.crypto_db.name
  description   = "CoinGecko cryptocurrency market data (Parquet)"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"                = "parquet"
    "parquet.compression"           = "SNAPPY"
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

    # Veri kolonlari (partition key'ler HARIC)
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
      type = "bigint"
    }
    columns {
      name = "total_volume"
      type = "bigint"
    }
    columns {
      name = "processed_at"
      type = "string"
    }
  }

  # Partition key'ler (S3 path'teki key=value ciftleri)
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
