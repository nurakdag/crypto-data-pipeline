##############################################################################
# S3 Event Notification
#
# Wires the raw bucket so that new objects trigger the Lambda function.
#
# Flow:
#   1. Airflow writes a JSON file to the raw bucket (PutObject)
#   2. S3 sends an event notification
#   3. Lambda is invoked and converts JSON -> Parquet
#
# NOTE: Two things are required for S3 event notifications to work:
#   a) Add a notification configuration to the S3 bucket
#   b) Grant Lambda a resource-based permission that allows S3 to invoke it
#   Missing either one results in silent failures that are hard to debug.
##############################################################################

# -----------------------------------------------------------------
# Lambda Permission
#
# Grants the S3 service permission to invoke this Lambda function.
# Without this, S3 events are silently dropped.
#
# source_arn scopes the permission to the raw bucket only —
# no other bucket can trigger this function.
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
# Triggers Lambda when an object matching the raw/ prefix and
# .json suffix lands in the raw bucket.
#
# filter_prefix and filter_suffix are important:
#   - Only objects under raw/ trigger the function
#   - Only .json files trigger the function
#   - Other file types (logs, csv, etc.) are ignored
#
# NOTE: A bucket supports only ONE notification configuration resource.
# If another service also needs notifications from this bucket,
# switch to an SNS/SQS fan-out pattern to avoid conflicts.
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
