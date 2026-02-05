##############################################################################
# IAM - Lambda Execution Role & Policies
#
# Principle of Least Privilege:
# Lambda SADECE ihtiyaci olan izinlere sahip olmali.
#   - Raw bucket'tan OKUMA (GetObject)
#   - Processed bucket'a YAZMA (PutObject)
#   - CloudWatch'a log yazma
#
# YANLIS ORNEK (yapma):
#   Effect = "Allow"
#   Action = "s3:*"
#   Resource = "*"
#
# Bu "her seye erisim ver" demek. Security review'da reddedilir.
# Her zaman spesifik action ve resource belirt.
##############################################################################

# -----------------------------------------------------------------
# Lambda Assume Role Policy
#
# Bu policy Lambda servisinin bu role "burunebilmesini" saglar.
# Her Lambda role'u icin bu zorunludur.
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
# Lambda'nin raw bucket'tan JSON dosyalarini okumasi icin.
# Sadece GetObject ve ListBucket izni veriyoruz.
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
# Lambda'nin processed bucket'a Parquet dosyalarini yazmasi icin.
# Sadece PutObject izni veriyoruz. DeleteObject YOK.
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
# Lambda'nin log yazabilmesi icin.
# AWS managed policy kullaniyoruz - tekerlek icat etmeye gerek yok.
# -----------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
