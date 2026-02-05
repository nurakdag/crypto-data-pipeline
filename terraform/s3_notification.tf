##############################################################################
# S3 Event Notification
#
# Bu dosya raw bucket'taki degisikliklerin Lambda'yi tetiklemesini saglar.
#
# Akis:
#   1. Airflow, raw bucket'a JSON dosyasi yazar (PutObject)
#   2. S3, event notification gonderi
#   3. Lambda tetiklenir ve JSON -> Parquet donusumu yapar
#
# DIKKAT: S3 event notification ayarlamak icin 2 sey gerekir:
#   a) S3 bucket'a notification configuration ekle
#   b) Lambda'ya "S3'ten tetiklenebilirsin" izni ver (permission)
#   Ikisini de yapmayan kisi debugging cehennemine duser.
##############################################################################

# -----------------------------------------------------------------
# Lambda Permission
#
# S3 servisine "bu Lambda'yi tetikleyebilirsin" diyen izin.
# Bu olmadan S3 event'i Lambda'ya ulasamaz.
#
# source_arn ile SADECE raw bucket'in tetikleyebilmesini sagliyoruz.
# Baska bir bucket bu Lambda'yi tetikleyemez.
# -----------------------------------------------------------------
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3InvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.json_to_parquet.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw.arn
}

# -----------------------------------------------------------------
# S3 Bucket Notification
#
# Raw bucket'a "raw/" prefix'ine ve ".json" suffix'ine
# uyan dosyalar geldiginde Lambda'yi tetikle.
#
# filter_prefix ve filter_suffix ONEMLI:
#   - Sadece raw/ altindaki dosyalar tetikler
#   - Sadece .json dosyalari tetikler
#   - Baska turlu dosyalar (log, csv, vs.) Lambda'yi tetiklemez
#
# DIKKAT: Bir bucket'ta sadece BIR notification configuration olabilir.
# Eger baska bir servis de notification kullaniyorsa conflict olur.
# Bu durumda SNS/SQS fan-out pattern'e gecilmeli.
# -----------------------------------------------------------------
resource "aws_s3_bucket_notification" "raw_bucket_notification" {
  bucket = aws_s3_bucket.raw.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.json_to_parquet.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.raw_prefix
    filter_suffix       = var.raw_suffix
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}
