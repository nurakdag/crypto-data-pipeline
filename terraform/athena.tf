##############################################################################
# AWS Athena - Serverless SQL Query Engine
#
# Athena nasil calisir?
#   1. Glue Data Catalog'daki tablo tanimini okur
#   2. S3'teki Parquet dosyalarini direkt sorgular (veriyi TASINMAZ)
#   3. Sorgu sonuclarini ayri bir S3 bucket'a yazar (CSV formatinda)
#
# Neden Redshift degil Athena?
#   - Redshift: Cluster calistirirsin, saat basina ~$0.25+ odersen
#     (ayda ~$180+ bos dursa bile)
#   - Athena: Serverless, SADECE taranan veri icin odme
#     Parquet ile 1TB sorgu = ~$5 (bizim veri cok kucuk, kuruslar)
#
# Maliyet kontrolu:
#   - Workgroup'ta "bytes_scanned_cutoff" ile sorgu limiti koyuyoruz
#   - Birisi SELECT * yaparsa bile limit asinca sorgu iptal olur
##############################################################################

# -----------------------------------------------------------------
# Athena Query Results Bucket
#
# Athena her sorgu sonucunu S3'e yazar (CSV olarak).
# Bu ZORUNLU - Athena sonucsuz calisamaz.
#
# 7 gun lifecycle rule: Sorgu sonuclari gecici data,
# uzun sure tutmaya gerek yok. Temiz tutalim.
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

    filter {} # Tum dosyalara uygula

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
# Workgroup = Athena'da izolasyon ve maliyet kontrolu birimi.
#
# enforce_workgroup_configuration = true:
#   Kullanici kendi output location'ini belirleyemez.
#   HER ZAMAN bizim tanimladigimiz bucket'a yazar.
#   Bu guvenlik icin onemli - birisi sonuclari baska yere yonlendiremez.
#
# bytes_scanned_cutoff_per_query:
#   Sorgu bu limiti asarsa otomatik iptal olur.
#   Maliyet korumasidir. Birisi yanlis sorgu yazarsa
#   milyarlarca satir taranmasini engeller.
#   1GB = ~$0.005 maliyet. Guvenli bir limit.
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
