# main.tf - Snowball Monitoring Terraform Module

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Variables
variable "snowball_devices" {
  description = "List of Snowball device IP addresses to monitor"
  type        = list(string)
  validation {
    condition     = length(var.snowball_devices) > 0
    error_message = "At least one Snowball device IP must be provided."
  }
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the monitoring instance"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "key_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed SSH access"
  type        = list(string)
  default     = []
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.nano"
}

variable "monitoring_interval" {
  description = "Monitoring interval in minutes"
  type        = number
  default     = 2
}

variable "deployment_type" {
  description = "Deployment type: public, private_nat, or private_endpoints"
  type        = string
  default     = "public"
  validation {
    condition     = contains(["public", "private_nat", "private_endpoints"], var.deployment_type)
    error_message = "Deployment type must be public, private_nat, or private_endpoints."
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["al2023-ami-*"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

# IAM Role and Policy
resource "aws_iam_policy" "snowball_monitoring" {
  name        = "SnowballMonitoringPolicy-${random_id.suffix.hex}"
  description = "Policy for Snowball monitoring instance"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = var.sns_topic_arn
      },
      {
        Sid    = "GetCallerIdentity"
        Effect = "Allow"
        Action = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "snowball_monitoring" {
  name = "SnowballMonitoringRole-${random_id.suffix.hex}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "snowball_monitoring" {
  role       = aws_iam_role.snowball_monitoring.name
  policy_arn = aws_iam_policy.snowball_monitoring.arn
}

resource "aws_iam_instance_profile" "snowball_monitoring" {
  name = "SnowballMonitoringProfile-${random_id.suffix.hex}"
  role = aws_iam_role.snowball_monitoring.name
}

# Security Group
resource "aws_security_group" "snowball_monitoring" {
  name_prefix = "snowball-monitoring-"
  description = "Security group for Snowball monitoring instance"
  vpc_id      = var.vpc_id

  # SSH access
  dynamic "ingress" {
    for_each = var.allowed_ssh_cidrs
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "SSH access from ${ingress.value}"
    }
  }

  # Outbound - Allow all HTTPS for AWS services
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to AWS services"
  }

  # Outbound - Snowball device connectivity
  dynamic "egress" {
    for_each = var.snowball_devices
    content {
      from_port   = 8443
      to_port     = 8443
      protocol    = "tcp"
      cidr_blocks = ["${egress.value}/32"]
      description = "Snowball device ${egress.value}"
    }
  }

  # Allow DNS
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS resolution"
  }

  # Allow NTP
  egress {
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "NTP time sync"
  }

  tags = {
    Name = "snowball-monitoring-sg"
  }
}

# User data script
locals {
  user_data = base64encode(templatefile("${path.module}/user-data.tpl", {
    snowball_devices     = var.snowball_devices
    sns_topic_arn       = var.sns_topic_arn
    monitoring_interval = var.monitoring_interval
    deployment_type     = var.deployment_type
  }))
}

# EC2 Instance
resource "aws_instance" "snowball_monitoring" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type              = var.instance_type
  key_name                   = var.key_name
  subnet_id                  = var.subnet_id
  vpc_security_group_ids     = [aws_security_group.snowball_monitoring.id]
  iam_instance_profile       = aws_iam_instance_profile.snowball_monitoring.name
  associate_public_ip_address = var.deployment_type == "public"
  user_data                  = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = {
    Name = "snowball-monitoring"
    Type = "monitoring"
    Project = "snowball-monitoring"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "any_device_offline" {
  alarm_name          = "Snowball-MultiDevice-AnyOffline"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "TotalOffline"
  namespace           = "Snowball/MultiDevice"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "0.5"
  alarm_description   = "Alert when any Snowball device goes offline"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions         = [var.sns_topic_arn]
  treat_missing_data  = "breaching"

  tags = {
    Name = "snowball-any-offline"
  }
}

resource "aws_cloudwatch_metric_alarm" "monitor_health" {
  alarm_name          = "Snowball-MultiDevice-Monitor-NotReporting"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TotalDevices"
  namespace           = "Snowball/MultiDevice"
  period              = "900"
  statistic           = "SampleCount"
  threshold           = "1"
  alarm_description   = "Alert when multi-device monitoring script stops reporting"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.sns_topic_arn]

  tags = {
    Name = "snowball-monitor-health"
  }
}

resource "aws_cloudwatch_metric_alarm" "all_devices_offline" {
  alarm_name          = "Snowball-MultiDevice-AllOffline-CRITICAL"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  datapoints_to_alarm = "2"
  metric_name         = "TotalOnline"
  namespace           = "Snowball/MultiDevice"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "0.5"
  alarm_description   = "CRITICAL: All Snowball devices are offline"
  alarm_actions       = [var.sns_topic_arn]
  treat_missing_data  = "breaching"

  tags = {
    Name = "snowball-all-offline-critical"
  }
}

# Random ID for unique naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Outputs
output "instance_id" {
  description = "ID of the monitoring instance"
  value       = aws_instance.snowball_monitoring.id
}

output "instance_private_ip" {
  description = "Private IP of the monitoring instance"
  value       = aws_instance.snowball_monitoring.private_ip
}

output "instance_public_ip" {
  description = "Public IP of the monitoring instance"
  value       = aws_instance.snowball_monitoring.public_ip
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.snowball_monitoring.id
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm names"
  value = {
    any_offline = aws_cloudwatch_metric_alarm.any_device_offline.alarm_name
    monitor_health = aws_cloudwatch_metric_alarm.monitor_health.alarm_name
    all_offline = aws_cloudwatch_metric_alarm.all_devices_offline.alarm_name
  }
}