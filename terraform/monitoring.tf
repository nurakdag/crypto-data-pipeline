##############################################################################
# Monitoring & Alerting - CloudWatch Alarms + SNS
#
# Sends automatic notifications when the pipeline breaks.
#
# Three alarms are defined:
#   1. Lambda Errors    — triggers when error count > 0
#   2. Lambda Duration  — triggers when duration > 60s (approaching timeout)
#   3. DLQ Messages     — triggers when messages appear in the DLQ
#
# All alarms publish to an SNS topic with an email subscription.
# IMPORTANT: After terraform apply, click the confirmation link in the
#            subscription email before alerts will be delivered.
##############################################################################

# -----------------------------------------------------------------
# SNS Topic — notification channel
#
# CloudWatch alarms publish to this topic.
# Any subscriber (email, Slack, PagerDuty, etc.) receives the notifications.
# -----------------------------------------------------------------
resource "aws_sns_topic" "pipeline_alerts" {
  name = "${var.project_name}-alerts-${var.environment}"

  tags = {
    Name = "${var.project_name}-alerts-${var.environment}"
  }
}

# -----------------------------------------------------------------
# SNS Email Subscription
#
# A confirmation email is sent after terraform apply.
# Alerts will not be delivered until the subscription is confirmed.
# -----------------------------------------------------------------
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# -----------------------------------------------------------------
# Alarm 1: Lambda Errors
#
# Fires when 1 or more errors occur within a 5-minute window.
# Examples: malformed JSON, S3 access denied, memory overflow.
# -----------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors-${var.environment}"
  alarm_description   = "Lambda function error detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.json_to_parquet.function_name
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
  ok_actions    = [aws_sns_topic.pipeline_alerts.arn]

  tags = {
    Name = "${var.project_name}-lambda-errors-${var.environment}"
  }
}

# -----------------------------------------------------------------
# Alarm 2: Lambda Duration
#
# Fires when execution time exceeds 60 s, indicating the function
# is approaching its 120 s timeout and needs investigation.
# -----------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.project_name}-lambda-duration-${var.environment}"
  alarm_description   = "Lambda duration exceeded 60 s — approaching timeout"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Maximum"
  threshold           = 60000 # 60 seconds in milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.json_to_parquet.function_name
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]

  tags = {
    Name = "${var.project_name}-lambda-duration-${var.environment}"
  }
}

# -----------------------------------------------------------------
# Alarm 3: DLQ Messages
#
# DLQ'da mesaj birikmisse event'ler basarisiz olmustur.
# Bu alarm "pipeline kirildi" anlamina gelir.
# -----------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.project_name}-dlq-messages-${var.environment}"
  alarm_description   = "DLQ'da basarisiz event'ler var - pipeline kirilmis olabilir"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.lambda_dlq.name
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
  ok_actions    = [aws_sns_topic.pipeline_alerts.arn]

  tags = {
    Name = "${var.project_name}-dlq-messages-${var.environment}"
  }
}
