##############################################################################
# Lambda Function & Layer
#
# Lambda fonksiyonu + pandas/pyarrow icin layer tanimlamalari.
#
# Lambda Layer nedir?
#   Lambda'nin varsayilan runtime'inda pandas ve pyarrow YOK.
#   Layer, bu kutuphaneleri Lambda'ya eklememizi saglar.
#   Boylece her deploy'da 50MB+ kutuphane yuklemek zorunda kalmayiz.
#
# Deployment akisi:
#   1. handler.py zip'lenir (archive_file ile)
#   2. Lambda function olusturulur
#   3. Layer ARN olarak eklenir (pandas + pyarrow)
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

  role    = aws_iam_role.lambda_role.arn
  timeout = var.lambda_timeout
  memory_size = var.lambda_memory

  # pandas + pyarrow layer
  layers = [
    aws_lambda_layer_version.pandas_layer.arn,
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
# Lambda Layer - pandas + pyarrow
#
# ONEMLI: Bu layer'i kendin build etmen gerekiyor.
# Lambda Linux (Amazon Linux 2023) uzerinde calisiyor,
# macOS veya Windows'ta pip install yapip zip'lersen CALISMAZ.
#
# Layer build etme adimlar (Docker ile):
#
#   mkdir -p lambda/layers/pandas
#   docker run --rm -v $(pwd)/lambda/layers/pandas:/out \
#     public.ecr.aws/lambda/python:3.12 \
#     bash -c "pip install pandas pyarrow -t /out/python && exit"
#   cd lambda/layers/pandas && zip -r ../pandas-layer.zip python/
#
# Sonra bu zip dosyasini asagidaki resource'a ver.
#
# Alternatif: AWS'nin sagladigi managed layer'lari kullanabilirsin:
#   arn:aws:lambda:eu-central-1:336392948345:layer:AWSSDKPandas-Python312:x
#   Bu ARN bolgeye gore degisir, kontrol et:
#   https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html
# -----------------------------------------------------------------
resource "aws_lambda_layer_version" "pandas_layer" {
  layer_name          = "${var.project_name}-pandas-pyarrow-${var.environment}"
  description         = "pandas and pyarrow for Python 3.12"
  filename            = "${path.module}/../lambda/layers/pandas-layer.zip"
  compatible_runtimes = ["python3.12"]

  lifecycle {
    # Layer zip dosyasi degismezse yeniden olusturma
    create_before_destroy = true
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
