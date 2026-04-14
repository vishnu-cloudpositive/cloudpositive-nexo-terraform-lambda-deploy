variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "function_name" {
  type    = string
  default = "ec2-resize-cat-001"
}

variable "slack_webhook_url" {
  type      = string
  sensitive = true
}

variable "servers" {
  type = list(object({
    name          = string
    instance_id   = string
    downsize_type = string
    upsize_type   = string
    downsize_cron = string
    upsize_cron   = string
  }))
}

variable "holidays" {
  type = list(string)
}
