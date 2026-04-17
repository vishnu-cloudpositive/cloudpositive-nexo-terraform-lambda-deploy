data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda/lambda_function.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "ec2-resizer-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = "ec2-resizer"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "ec2-resizer-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:ModifyInstanceAttribute"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "ec2_resizer" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = var.function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  memory_size      = 128
  timeout          = 60

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      HOLIDAYS          = jsonencode(var.holidays)
    }
  }

  tags = {
    Project = "ec2-resizer"
  }
}

resource "aws_iam_role" "scheduler_role" {
  name = "ec2-resizer-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  inline_policy {
    name = "allow-lambda-invoke"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = "lambda:InvokeFunction"
          Resource = aws_lambda_function.ec2_resizer.arn
        }
      ]
    })
  }

  tags = {
    Project = "ec2-resizer"
  }
}

resource "aws_scheduler_schedule" "downsize" {
  for_each = { for s in var.servers : s.name => s }

  name       = "ec2-resizer-${each.value.name}-downsize"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(${each.value.downsize_cron})"
  schedule_expression_timezone = "Asia/Kolkata"

  target {
    arn      = aws_lambda_function.ec2_resizer.arn
    role_arn = aws_iam_role.scheduler_role.arn

    input = jsonencode({
      instance_id = each.value.instance_id
      target_type = each.value.downsize_type
      region      = var.region
    })
  }
}

resource "aws_scheduler_schedule" "upsize" {
  for_each = { for s in var.servers : s.name => s }

  name       = "ec2-resizer-${each.value.name}-upsize"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(${each.value.upsize_cron})"
  schedule_expression_timezone = "Asia/Kolkata"

  target {
    arn      = aws_lambda_function.ec2_resizer.arn
    role_arn = aws_iam_role.scheduler_role.arn

    input = jsonencode({
      instance_id = each.value.instance_id
      target_type = each.value.upsize_type
      region      = var.region
    })
  }
}
