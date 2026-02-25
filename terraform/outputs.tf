##############################################################################
# Outputs
#
# Printed to stdout after terraform apply.
# Consumed by other Terraform modules or CI/CD pipelines.
#
# Usage: terraform output processed_bucket_name
##############################################################################

output "processed_bucket_name" {
  description = "Processed (Parquet) S3 bucket name"
  value       = aws_s3_bucket.processed.id
}

output "processed_bucket_arn" {
  description = "Processed S3 bucket ARN"
  value       = aws_s3_bucket.processed.arn
}

output "raw_bucket_name" {
  description = "Raw (JSON) S3 bucket name"
  value       = aws_s3_bucket.raw.id
}

output "raw_bucket_arn" {
  description = "Raw S3 bucket ARN"
  value       = aws_s3_bucket.raw.arn
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.json_to_parquet.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.json_to_parquet.arn
}

output "lambda_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# -----------------------------------------------------------------
# Glue & Athena Outputs
# -----------------------------------------------------------------

output "glue_database_name" {
  description = "Glue Data Catalog database name — used in Athena queries as FROM <name>.table"
  value       = aws_glue_catalog_database.crypto_db.name
}

output "glue_table_coingecko" {
  description = "CoinGecko Glue table name"
  value       = aws_glue_catalog_table.coins_markets.name
}

output "athena_workgroup_name" {
  description = "Athena workgroup name — specify this when running queries"
  value       = aws_athena_workgroup.crypto_workgroup.name
}

output "athena_results_bucket" {
  description = "S3 bucket where Athena query results are written"
  value       = aws_s3_bucket.athena_results.id
}

# -----------------------------------------------------------------
# DLQ Outputs
# -----------------------------------------------------------------

output "dlq_url" {
  description = "Dead Letter Queue URL — use this to inspect and replay failed events"
  value       = aws_sqs_queue.lambda_dlq.url
}

output "dlq_arn" {
  description = "Dead Letter Queue ARN"
  value       = aws_sqs_queue.lambda_dlq.arn
}

# -----------------------------------------------------------------
# Monitoring Outputs
# -----------------------------------------------------------------

output "sns_topic_arn" {
  description = "Pipeline alert SNS topic ARN"
  value       = aws_sns_topic.pipeline_alerts.arn
}
