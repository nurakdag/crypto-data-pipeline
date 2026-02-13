##############################################################################
# AWS Glue - Data Catalog Database & Table
#
# Crawler KULLANMIYORUZ. Neden?
#   1. Crawler IAM + Lake Formation yetki karmasikligi
#   2. Crawler calistirmak maliyet (DPU-saat)
#   3. Biz semayi zaten biliyoruz, kesfetmeye gerek yok
#
# Bunun yerine:
#   - Glue Catalog Table'i Terraform ile elle tanimliyoruz
#   - Athena Partition Projection ile yeni partition'lar ANINDA bulunuyor
#   - Crawler'a gerek yok, maliyet $0
#
# Partition Projection nedir?
#   Athena'ya diyoruz ki: "date partition'i 2026-01-01 ile 2026-12-31 arasi,
#   hour partition'i 00 ile 23 arasi olacak. S3'te dosya var mi yok mu
#   kontrol etme, direkt sorgula." Bu sayede:
#   - Yeni partition eklediginde (yeni gun/saat) Athena ANINDA gorur
#   - MSCK REPAIR TABLE calistirmaya gerek yok
#   - Crawler calistirmaya gerek yok
##############################################################################

# -----------------------------------------------------------------
# Lake Formation Ayarlari
#
# Yeni AWS hesaplarinda Lake Formation varsayilan olarak acik gelir.
# IAM_ALLOWED_PRINCIPALS ayari Lake Formation'a diyor ki:
#   "IAM yetkisi olan herkese Data Catalog erisimi ver"
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
# Tablo semayi ve partition'lari tanimlar.
# Athena bu tanimi kullanarak S3'teki Parquet'leri sorgular.
#
# Partition Projection:
#   Athena'ya partition degerlerinin araligini soyluyoruz.
#   Boylece her yeni partition icin metadata guncellemeye gerek yok.
#
# S3 path yapisi:
#   processed/source=coingecko/dataset=coins_markets/date=2026-02-05/hour=12/data_*.parquet
# -----------------------------------------------------------------
resource "aws_glue_catalog_table" "coins_markets" {
  name          = "coins_markets"
  database_name = aws_glue_catalog_database.crypto_db.name
  description   = "CoinGecko cryptocurrency market data (Parquet)"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"                  = "parquet"
    "parquet.compression"             = "SNAPPY"
    # Partition Projection ayarlari
    "projection.enabled"              = "true"
    "projection.source.type"          = "enum"
    "projection.source.values"        = "coingecko"
    "projection.dataset.type"         = "enum"
    "projection.dataset.values"       = "coins_markets"
    "projection.date.type"            = "date"
    "projection.date.format"          = "yyyy-MM-dd"
    "projection.date.range"           = "2026-01-01,NOW"
    "projection.date.interval"        = "1"
    "projection.date.interval.unit"   = "DAYS"
    "projection.hour.type"            = "integer"
    "projection.hour.range"           = "0,23"
    "projection.hour.digits"          = "2"
    "storage.location.template"       = "s3://${aws_s3_bucket.processed.id}/processed/source=$${source}/dataset=$${dataset}/date=$${date}/hour=$${hour}"
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
