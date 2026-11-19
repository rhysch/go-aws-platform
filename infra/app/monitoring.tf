resource "aws_sns_topic" "alerts" { name = "${var.project}-alerts" }
resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
resource "aws_cloudwatch_metric_alarm" "app" {
  alarm_name          = "${var.project}-app-unhealthy"
  alarm_description   = "Local HTTP health checks failed or stopped reporting; inspect SSM and application logs"
  namespace           = "GoAWSPlatform"
  metric_name         = "AppHealthy"
  dimensions          = { Project = var.project }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
resource "aws_cloudwatch_metric_alarm" "instance" {
  alarm_name          = "${var.project}-instance-status"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.app.id }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${var.project}-high-cpu"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.app.id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# A queue makes alarm delivery verifiable without sending email to anyone.
resource "aws_sqs_queue" "alerts" {
  name                      = "${var.project}-alerts"
  message_retention_seconds = 86400
  sqs_managed_sse_enabled   = true
}
resource "aws_sqs_queue_policy" "alerts" {
  queue_url = aws_sqs_queue.alerts.url
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "sns.amazonaws.com" },
    Action    = "sqs:SendMessage", Resource = aws_sqs_queue.alerts.arn,
    Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.alerts.arn } }
  }] })
}
resource "aws_sns_topic_subscription" "queue" {
  topic_arn            = aws_sns_topic.alerts.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.alerts.arn
  raw_message_delivery = true
  depends_on           = [aws_sqs_queue_policy.alerts]
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "OwnerAdministration", Effect = "Allow", Principal = { AWS = "${local.prefix}:iam::${data.aws_caller_identity.current.account_id}:root" }, Action = ["SNS:GetTopicAttributes", "SNS:SetTopicAttributes", "SNS:AddPermission", "SNS:RemovePermission", "SNS:DeleteTopic", "SNS:Subscribe", "SNS:ListSubscriptionsByTopic", "SNS:Publish"], Resource = aws_sns_topic.alerts.arn },
    { Sid = "CloudWatchAlarms", Effect = "Allow", Principal = { Service = "cloudwatch.amazonaws.com" }, Action = "SNS:Publish", Resource = aws_sns_topic.alerts.arn,
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id },
        ArnLike      = { "aws:SourceArn" = "${local.prefix}:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.project}-*" }
      }
    }
  ] })
}
