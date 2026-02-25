##############################################################################
# Lambda Function & Layer
#
# What is a Lambda Layer?
#   The default Lambda runtime does not include pandas or pyarrow.
#   A Layer lets us bundle these libraries and attach them to the function.
#
# We use the AWS-managed AWSSDKPandas layer:
#   - Published by AWS for every region
#   - Includes pandas, pyarrow, numpy, and aws-sdk-pandas (awswrangler)
#   - We don't build or maintain it — AWS does
#   - A separate ARN exists for each Python version
#
# Why a managed layer?
#   - No Docker build step required
#   - AWS handles updates and security patches
#   - Stable and production-tested
#
# ARN reference:
#   https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html
##############################################################################

# -----------------------------------------------------------------
# Lambda deployment package
#
# Automatically zips handler.py on every terraform plan.
# Terraform compares the file hash and skips re-deployment
# if the source code has not changed.
# -----------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/src"
  output_path = "${path.module}/../lambda/build/handler.zip"
}

# -----------------------------------------------------------------
# Lambda Function
# -----------------------------------------------------------------
# -----------------------------------------------------------------
# SQS Dead Letter Queue (DLQ)
#
# If Lambda fails after 2 retries, the event is sent here instead of
# being dropped. Failed events can be inspected and replayed later.
#
# message_retention_seconds = 14 days (maximum allowed)
# Lambda retry policy: MaximumRetryAttempts = 2 (default)
# -----------------------------------------------------------------
resource "aws_sqs_queue" "lambda_dlq" {
  name                       = "${var.project_name}-lambda-dlq-${var.environment}"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 300

  tags = {
    Name = "${var.project_name}-lambda-dlq-${var.environment}"
  }
}

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
  # Maintained by AWS — we do not build or package this ourselves.
  # ARN format: arn:aws:lambda:<REGION>:336392948345:layer:AWSSDKPandas-Python312:<VERSION>
  layers = [
    "arn:aws:lambda:${var.aws_region}:336392948345:layer:AWSSDKPandas-Python312:15",
  ]

  # Dead Letter Queue: Lambda basarisiz olursa event SQS'e gider
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

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
# Lambda creates a log group automatically, but with infinite retention.
# We pre-create it here with a 30-day retention policy to control costs.
# -----------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.json_to_parquet.function_name}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-lambda-logs-${var.environment}"
  }
}
