resource "aws_sns_topic" "slack_alerts" {
  name = "slack-alerts-${var.environment}"
  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role" "cloudwatch_alert_lambda_role" {
  name               = "cloudwatch-alert-lambda-role-${var.environment}"
  assume_role_policy = <<EOF
  {
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
  }
  EOF

  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_policy" "cloudwatch_alert_lambda_policy" {

  name        = "cloudwatch-alert-lambda-policy-${var.environment}"
  description = "AWS IAM Policy for managing aws lambda role"
  policy      = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": [
       "logs:CreateLogGroup",
       "logs:CreateLogStream",
       "logs:PutLogEvents"
     ],
     "Resource": "arn:aws:logs:*:*:*",
     "Effect": "Allow"
   },
   {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "${aws_sns_topic.slack_alerts.arn}"
   }
 ]
}
EOF
  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "attach_cloudwatch_alert_iam_policy_to_cloudwatch_alert_iam_role" {
  role       = aws_iam_role.cloudwatch_alert_lambda_role.name
  policy_arn = aws_iam_policy.cloudwatch_alert_lambda_policy.arn
}

data "archive_file" "cloudwatch_alert_lambda_code_zip" {
  type        = "zip"
  source_dir  = "../assets/lambda-cloudwatch-alert/"
  output_path = var.cw_alert_lambda_func_path
}

resource "aws_lambda_function" "cloudwatch_alert" {
  filename      = var.cw_alert_lambda_func_path
  function_name = "cloudwatch-alert-function-${var.environment}"
  role          = aws_iam_role.cloudwatch_alert_lambda_role.arn
  handler       = "alert.lambda_handler"
  runtime       = "python3.9"
  depends_on    = [aws_iam_role_policy_attachment.attach_cloudwatch_alert_iam_policy_to_cloudwatch_alert_iam_role]

  environment {
    variables = {
      SLACK_WEBHOOK = var.slack_alert_hook
    }
  }
  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "cloudwatch_alert_subscription" {
  topic_arn = aws_sns_topic.slack_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.cloudwatch_alert.arn
}

resource "aws_lambda_permission" "sns_invoke_lambda" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cloudwatch_alert.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.slack_alerts.arn
}

resource "aws_cloudwatch_event_rule" "cloudwatch_alert_event_rule" {
  name          = "cloudwatch-alert-event-rule-${var.environment}"
  description   = "Capture CloudWatch Alarm state changes"
  event_pattern = <<EOF
{
  "source": ["aws.cloudwatch"],
  "detail-type": ["CloudWatch Alarm State Change"],
  "detail": {
    "state": {
      "value": [
        "ALARM","OK"
      ]
    }
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "cloudwatch_alert_event_target" {
  rule      = aws_cloudwatch_event_rule.cloudwatch_alert_event_rule.name
  arn       = aws_sns_topic.slack_alerts.arn
  target_id = "slack_alerts_target"
}

resource "aws_cloudwatch_metric_alarm" "msgc_rds_cpu_utilization" {
  alarm_name          = "msgc-rds-cpu-utilization-${var.environment}"
  alarm_description   = "This metric checks CPU utilization for RDS PostgreSQL"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_sns_topic.slack_alerts.arn]
  ok_actions          = [aws_sns_topic.slack_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = "msgc-${var.environment}"
  }
  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "msgc_rds_free_storage_space" {
  alarm_name          = "msgc-rds-free-storage-space-${var.environment}"
  alarm_description   = "This metric checks free storage for RDS PostgreSQL"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Minimum"
  threshold           = 10 * var.gb_to_mb
  alarm_actions       = [aws_sns_topic.slack_alerts.arn]
  ok_actions          = [aws_sns_topic.slack_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = "msgc-${var.environment}"
  }
  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "msgc_rds_connections" {
  alarm_name          = "msgc-rds-connections-${var.environment}"
  alarm_description   = "This metric checks number of connection"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Maximum"
  threshold           = 250
  alarm_actions       = [aws_sns_topic.slack_alerts.arn]
  ok_actions          = [aws_sns_topic.slack_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = "msgc-${var.environment}"
  }
  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "datacore_docdb_cpu_utilization" {
  alarm_name          = "datacore-docdb-cpu-utilization-${var.environment}"
  alarm_description   = "This metric checks CPU utilization for DocDB"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/DocDB"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_sns_topic.slack_alerts.arn]
  ok_actions          = [aws_sns_topic.slack_alerts.arn]

  dimensions = {
    DBClusterIdentifier = module.docdb_datacore.cluster_name
  }
  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "datacore_docdb_storage_used" {
  alarm_name          = "datacore-docdb-storage-used-${var.environment}"
  alarm_description   = "This metric checks free storage for DocDB"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "VolumeBytesUsed"
  namespace           = "AWS/DocDB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 50 * var.gb_to_mb
  alarm_actions       = [aws_sns_topic.slack_alerts.arn]
  ok_actions          = [aws_sns_topic.slack_alerts.arn]
  treat_missing_data  = "ignore"

  dimensions = {
    DBClusterIdentifier = module.docdb_datacore.cluster_name
  }
  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "datacore_docdb_connections" {
  alarm_name          = "datacore-docdb-connections-number-${var.environment}"
  alarm_description   = "This metric checks number of connection for DocDB"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/DocDB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 50
  alarm_actions       = [aws_sns_topic.slack_alerts.arn]
  ok_actions          = [aws_sns_topic.slack_alerts.arn]

  dimensions = {
    DBClusterIdentifier = module.docdb_datacore.cluster_name
  }
  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}
