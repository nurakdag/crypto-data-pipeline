##############################################################################
# Outputs
#
# terraform apply sonrasinda ekrana basilir.
# Diger Terraform modulleri veya CI/CD pipeline'lari bu degerleri kullanabilir.
#
# Kullanim: terraform output processed_bucket_name
##############################################################################

output "processed_bucket_name" {
  description = "Processed (Parquet) S3 bucket adi"
  value       = aws_s3_bucket.processed.id
}

output "processed_bucket_arn" {
  description = "Processed S3 bucket ARN"
  value       = aws_s3_bucket.processed.arn
}

output "raw_bucket_name" {
  description = "Raw (JSON) S3 bucket adi"
  value       = aws_s3_bucket.raw.id
}

output "raw_bucket_arn" {
  description = "Raw S3 bucket ARN"
  value       = aws_s3_bucket.raw.arn
}

output "lambda_function_name" {
  description = "Lambda function adi"
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
  description = "CloudWatch log group adi"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# -----------------------------------------------------------------
# Glue & Athena Outputs
# -----------------------------------------------------------------

output "glue_database_name" {
  description = "Glue Data Catalog database adi - Athena'da FROM <bu_isim>.tablo seklinde kullanilir"
  value       = aws_glue_catalog_database.crypto_db.name
}

output "glue_crawler_name" {
  description = "Glue Crawler adi - elle calistirmak icin: aws glue start-crawler --name <bu_isim>"
  value       = aws_glue_crawler.processed_crawler.name
}

output "athena_workgroup_name" {
  description = "Athena workgroup adi - sorgu calistirirken kullanilir"
  value       = aws_athena_workgroup.crypto_workgroup.name
}

output "athena_results_bucket" {
  description = "Athena sorgu sonuclarinin yazildigi S3 bucket"
  value       = aws_s3_bucket.athena_results.id
}
