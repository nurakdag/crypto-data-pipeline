##############################################################################
# IAM - Lambda Execution Role & Policies
#
# Principle of Least Privilege:
# Lambda should have only the permissions it actually needs:
#   - READ from the raw bucket (GetObject)
#   - WRITE to the processed bucket (PutObject)
#   - WRITE logs to CloudWatch
#
# Anti-pattern to avoid:
#   Effect = "Allow"
#   Action = "s3:*"
#   Resource = "*"
#
# This grants access to everything and will fail any security review.
# Always specify exact actions and scoped resource ARNs.
##############################################################################

# -----------------------------------------------------------------
# Lambda Assume Role Policy
#
# Allows the Lambda service to assume this role.
# Required for every Lambda execution role.
# -----------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project_name}-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-lambda-role-${var.environment}"
  }
}

# -----------------------------------------------------------------
# S3 Read Policy (Raw Bucket)
#
# Allows Lambda to read JSON files from the raw bucket.
# Only GetObject and ListBucket are granted — nothing more.
# -----------------------------------------------------------------
data "aws_iam_policy_document" "lambda_s3_read" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${aws_s3_bucket.raw.arn}/raw/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.raw.arn,
    ]
  }
}

resource "aws_iam_policy" "lambda_s3_read" {
  name   = "${var.project_name}-lambda-s3-read-${var.environment}"
  policy = data.aws_iam_policy_document.lambda_s3_read.json
}

resource "aws_iam_role_policy_attachment" "lambda_s3_read" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3_read.arn
}

# -----------------------------------------------------------------
# S3 Write Policy (Processed Bucket)
#
# Allows Lambda to write Parquet files to the processed bucket.
# Only PutObject is granted — no DeleteObject.
# -----------------------------------------------------------------
data "aws_iam_policy_document" "lambda_s3_write" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
    ]
    resources = [
      "${aws_s3_bucket.processed.arn}/processed/*",
    ]
  }
}

resource "aws_iam_policy" "lambda_s3_write" {
  name   = "${var.project_name}-lambda-s3-write-${var.environment}"
  policy = data.aws_iam_policy_document.lambda_s3_write.json
}

resource "aws_iam_role_policy_attachment" "lambda_s3_write" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3_write.arn
}

# -----------------------------------------------------------------
# CloudWatch Logs Policy
#
# Allows Lambda to write logs to CloudWatch.
# Uses the AWS-managed policy — no need to reinvent the wheel.
# -----------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -----------------------------------------------------------------
# SQS DLQ Write Policy
#
# Allows Lambda to send failed events to the Dead Letter Queue.
# Only SendMessage is granted — no read or delete permissions.
# -----------------------------------------------------------------
data "aws_iam_policy_document" "lambda_sqs_dlq" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
    ]
    resources = [
      aws_sqs_queue.lambda_dlq.arn,
    ]
  }
}

resource "aws_iam_policy" "lambda_sqs_dlq" {
  name   = "${var.project_name}-lambda-sqs-dlq-${var.environment}"
  policy = data.aws_iam_policy_document.lambda_sqs_dlq.json
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_dlq" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_sqs_dlq.arn
}
