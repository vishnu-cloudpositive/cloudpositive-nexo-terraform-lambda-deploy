output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.ec2_resizer.arn
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.ec2_resizer.function_name
}

output "lambda_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda_role.arn
}

output "scheduler_role_arn" {
  description = "Scheduler IAM role ARN"
  value       = aws_iam_role.scheduler_role.arn
}

output "downsize_schedules" {
  description = "Downsize schedule names"
  value       = { for k, v in aws_scheduler_schedule.downsize : k => v.name }
}

output "upsize_schedules" {
  description = "Upsize schedule names"
  value       = { for k, v in aws_scheduler_schedule.upsize : k => v.name }
}
