##############################################################################
# AWS Glue - Data Catalog Database & Crawler
#
# Glue Crawler ne yapar?
#   1. S3'teki Parquet dosyalarini tarar
#   2. Sema (kolon isimleri, tipleri) otomatik kesfeder
#   3. Hive partition'lari (source, dataset, date, hour) otomatik bulur
#   4. Glue Data Catalog'a tablo olarak kaydeder
#   5. Athena bu tabloyu SQL ile sorgular
#
# Neden elle tablo tanimlamiyoruz?
#   - Crawler schema degisikliklerini otomatik yakalar
#   - Yeni partition eklendiginde (yeni gun, yeni saat) otomatik gunceller
#   - Elle partition eklemek (ALTER TABLE ADD PARTITION) ile ugrasmaya gerek yok
#
# Maliyet:
#   - Crawler: ~$0.44/DPU-saat (genelde saniyeler surer, aylik <$1)
#   - Glue Data Catalog: Ilk 1M obje ucretsiz
##############################################################################

# -----------------------------------------------------------------
# Glue Catalog Database
#
# Athena'da "FROM crypto_db.tablo_adi" dediginde
# bu database'e bakar. Mantiksal gruplama.
# -----------------------------------------------------------------
resource "aws_glue_catalog_database" "crypto_db" {
  name = "${replace(var.project_name, "-", "_")}_${var.environment}"

  description = "Crypto data pipeline - processed Parquet tablolari (${var.environment})"
}

# -----------------------------------------------------------------
# Glue Crawler IAM Role
#
# Crawler'in S3'ten okumasi ve Data Catalog'a yazmasi icin.
# Lambda role'unden AYRI bir role - her servis kendi role'unu kullanir.
# -----------------------------------------------------------------
data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_crawler_role" {
  name               = "${var.project_name}-glue-crawler-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json

  tags = {
    Name = "${var.project_name}-glue-crawler-role-${var.environment}"
  }
}

# AWS Managed Policy: Glue servis izinleri (Data Catalog yazma, CloudWatch log)
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom Policy: Processed bucket'tan Parquet dosyalarini okuma
data "aws_iam_policy_document" "glue_s3_read" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.processed.arn,
      "${aws_s3_bucket.processed.arn}/*",
    ]
  }
}

resource "aws_iam_policy" "glue_s3_read" {
  name   = "${var.project_name}-glue-s3-read-${var.environment}"
  policy = data.aws_iam_policy_document.glue_s3_read.json
}

resource "aws_iam_role_policy_attachment" "glue_s3_read" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = aws_iam_policy.glue_s3_read.arn
}

# -----------------------------------------------------------------
# Glue Crawler
#
# S3 processed bucket'taki Parquet dosyalarini tarar.
#
# Onemli ayarlar:
#   - recrawl_policy: CRAWL_NEW_FOLDERS_ONLY
#     Sadece yeni eklenen klasorleri tarar, tamamini degil.
#     Bu MALIYET TASARRUFU saglar.
#
#   - schema_change_policy: UPDATE_IN_DATABASE
#     Schema degisirse (yeni kolon eklenirse) tabloyu gunceller.
#     LOG: Degisiklikleri CloudWatch'a loglar.
#
#   - schedule: Saatte bir veya on-demand
#     Surekli calistirmak gereksiz maliyet.
# -----------------------------------------------------------------
resource "aws_glue_crawler" "processed_crawler" {
  name          = "${var.project_name}-processed-crawler-${var.environment}"
  database_name = aws_glue_catalog_database.crypto_db.name
  role          = aws_iam_role.glue_crawler_role.arn
  description   = "Crawls processed Parquet files from S3"

  s3_target {
    path = "s3://${aws_s3_bucket.processed.id}/processed/"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_NEW_FOLDERS_ONLY"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  # Saatte bir calistir (isteye bagli, on-demand de olabilir)
  schedule = var.glue_crawler_schedule

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  tags = {
    Name = "${var.project_name}-processed-crawler-${var.environment}"
  }
}
