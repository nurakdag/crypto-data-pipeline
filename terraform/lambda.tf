##############################################################################
# Lambda Function & Layer
#
# Lambda Layer nedir?
#   Lambda'nin varsayilan runtime'inda pandas ve pyarrow YOK.
#   Layer, bu kutuphaneleri Lambda'ya eklememizi saglar.
#
# Biz AWS'nin HAZIR managed layer'ini kullaniyoruz (AWSSDKPandas).
#   - AWS bunu her region icin yayinliyor
#   - Icinde pandas, pyarrow, numpy ve aws-sdk-pandas (awswrangler) var
#   - Biz build etmiyoruz, AWS maintain ediyor
#   - Her Python version icin ayri ARN var
#
# Neden managed layer?
#   - Docker ile build etme derdi yok
#   - AWS guncelleme ve guvenlik yamalarini kendisi yapiyor
#   - Production'da stabil ve test edilmis
#
# ARN referansi:
#   https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html
##############################################################################

# -----------------------------------------------------------------
# Lambda deployment package
#
# handler.py'yi otomatik zip'ler.
# Terraform her plan'da hash kontrol eder,
# dosya degismemisse tekrar deploy etmez.
# -----------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/src"
  output_path = "${path.module}/../lambda/build/handler.zip"
}

# -----------------------------------------------------------------
# Lambda Function
# -----------------------------------------------------------------
resource "aws_lambda_function" "json_to_parquet" {
  function_name = "${var.project_name}-json-to-parquet-${var.environment}"
  description   = "Converts raw JSON from S3 to Parquet format"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"

  role        = aws_iam_role.lambda_role.arn
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory

  # AWS Managed Layer: AWSSDKPandas (pandas + pyarrow + numpy)
  # Bu layer AWS tarafindan maintain ediliyor, biz build etmiyoruz.
  # ARN formati: arn:aws:lambda:<REGION>:336392948345:layer:AWSSDKPandas-Python312:<VERSION>
  layers = [
    "arn:aws:lambda:${var.aws_region}:336392948345:layer:AWSSDKPandas-Python312:15",
  ]

  environment {
    variables = {
      PROCESSED_BUCKET = aws_s3_bucket.processed.id
    }
  }

  tags = {
    Name = "${var.project_name}-json-to-parquet-${var.environment}"
  }
}

# -----------------------------------------------------------------
# CloudWatch Log Group
#
# Lambda otomatik log group olusturur ama retention suresi
# sonsuz olur. Biz 30 gun diyoruz, maliyet kontrolu icin.
# -----------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.json_to_parquet.function_name}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-lambda-logs-${var.environment}"
  }
}
