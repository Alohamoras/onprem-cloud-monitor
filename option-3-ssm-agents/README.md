# SSM Agent Installation and CloudWatch Monitoring Script

A single bash script solution for installing AWS Systems Manager (SSM) Agent on on-premises VMs with automated CloudWatch heartbeat monitoring.

## Features

- 🚀 **One-script deployment** - Single bash script with configuration variables at the top
- 🔧 **Auto-detection** - Automatically detects OS and architecture
- ☁️ **AWS automation** - Creates IAM roles and hybrid activations automatically
- 📊 **Heartbeat monitoring** - Sets up CloudWatch alarms for SSM agent failures
- 📧 **Email alerts** - Notifies you when VMs lose connectivity
- 🖥️ **Multi-OS support** - Works on Ubuntu, Debian, RHEL, CentOS, Rocky Linux, AlmaLinux, and Amazon Linux

## Prerequisites

- **Root access** on target VMs (via SSH)
- **AWS Account** with appropriate permissions
- **AWS CLI credentials** with permissions to:
  - Create IAM roles and policies
  - Create SSM hybrid activations
  - Create CloudWatch alarms
  - Publish to SNS topics
- **SNS Topic** for email notifications (instructions below)
- **Network connectivity** from VMs to AWS endpoints

## Quick Start

### 1. Create SNS Topic for Alerts

#### Option A: Using AWS CLI
```bash
# Create topic
aws sns create-topic --name SSM-Alerts --region us-east-1

# Subscribe your email
aws sns subscribe \
    --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:SSM-Alerts \
    --protocol email \
    --notification-endpoint your-email@example.com

# Confirm subscription via email
```

#### Option B: Using AWS Console
1. Go to [AWS SNS Console](https://console.aws.amazon.com/sns/)
2. Click **Create topic** → Choose **Standard**
3. Name it `SSM-Alerts`
4. After creation, click on the topic
5. Click **Create subscription**
6. Protocol: **Email**, Endpoint: **your-email@example.com**
7. Check your email and confirm the subscription
8. Copy the Topic ARN for the script

### 2. Configure the Script

Edit the configuration variables at the top of `install-ssm.sh`:

```bash
# Required AWS Configuration
AWS_REGION="us-east-1"                    
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
AWS_ACCOUNT_ID="123456789012"

# SNS Topic for Alerts
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:SSM-Alerts"

# Optional Customization
INSTANCE_NAME_PREFIX="onprem"             # Prefix for instance names
ALARM_THRESHOLD_MINUTES=10                # Minutes before alerting
```

### 3. Deploy to VMs

```bash
# Copy script to VM
scp install-ssm.sh user@your-vm:/tmp/

# SSH to VM and run as root
ssh user@your-vm
sudo bash /tmp/install-ssm.sh
```

## Configuration Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AWS_REGION` | Yes | us-east-1 | AWS region for SSM registration |
| `AWS_ACCESS_KEY_ID` | Yes | - | AWS access key with required permissions |
| `AWS_SECRET_ACCESS_KEY` | Yes | - | AWS secret access key |
| `AWS_ACCOUNT_ID` | Yes | - | Your 12-digit AWS account ID |
| `SNS_TOPIC_ARN` | No* | - | SNS topic ARN for CloudWatch alerts |
| `ENABLE_CLOUDWATCH_ALARMS` | No | true | Enable/disable alarm creation |
| `ALARM_THRESHOLD_MINUTES` | No | 10 | Minutes without heartbeat before alarm |
| `INSTANCE_NAME_PREFIX` | No | onprem | Prefix for instance identification |
| `SSM_ROLE_NAME` | No | SSMServiceRole | IAM role name for SSM |
| `MAX_INSTANCES` | No | 100 | Max instances per activation |
| `ACTIVATION_EXPIRY_DAYS` | No | 30 | Days until activation expires |

*Required if `ENABLE_CLOUDWATCH_ALARMS` is true

## What the Script Does

1. **Installs AWS CLI** (if not present)
2. **Installs SSM Agent** appropriate for your OS/architecture
3. **Creates IAM Role** with necessary SSM permissions
4. **Creates Hybrid Activation** in AWS Systems Manager
5. **Registers the VM** with AWS Systems Manager
6. **Starts SSM Agent** service
7. **Creates CloudWatch Alarms**:
   - Individual alarm for this specific instance
   - Fleet-wide alarm for any instance failure (created once)
8. **Verifies Connection** and confirms heartbeat is active

## CloudWatch Alarms

The script creates two types of alarms:

### Per-Instance Alarm
- **Name**: `SSM-Heartbeat-Failed-{PREFIX}-{hostname}`
- **Purpose**: Identifies exactly which VM is having issues
- **Trigger**: No heartbeat for 10 minutes

### Fleet-Wide Alarm
- **Name**: `SSM-Heartbeat-Failed-{PREFIX}-ANY`
- **Purpose**: Detects if ANY instance loses connectivity
- **Trigger**: Any instance without heartbeat for 10 minutes
- **Note**: Only created by the first instance

## Monitoring

After installation, you can monitor your instances through:

- **SSM Console**: [Systems Manager Fleet Manager](https://console.aws.amazon.com/systems-manager/managed-instances)
- **CloudWatch Alarms**: [CloudWatch Console](https://console.aws.amazon.com/cloudwatch/)
- **Email Notifications**: Sent to your configured email when heartbeat fails

## Troubleshooting

### Script Fails to Run
- Ensure you're running as root: `sudo bash install-ssm.sh`
- Check AWS credentials are correct
- Verify network connectivity to AWS

### Instance Not Appearing in SSM Console
- Wait 2-3 minutes for initial registration
- Check SSM Agent status: `sudo systemctl status amazon-ssm-agent`
- Verify IAM role has correct permissions
- Check network connectivity to SSM endpoints

### Alarms Not Creating
- Verify SNS_TOPIC_ARN is set correctly
- Ensure AWS credentials have CloudWatch permissions
- Check if alarm already exists in CloudWatch console

### Not Receiving Email Alerts
- Confirm SNS subscription (check spam folder)
- Verify SNS topic ARN is correct
- Test SNS topic manually from AWS console
- Check CloudWatch alarm state in console

## Required AWS Permissions

The AWS credentials used need the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:GetRole",
        "ssm:CreateActivation",
        "ssm:DescribeInstanceInformation",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DescribeAlarms",
        "sns:Publish"
      ],
      "Resource": "*"
    }
  ]
}
```

## Network Requirements

VMs need outbound HTTPS (443) access to:
- `ssm.{region}.amazonaws.com`
- `ssmmessages.{region}.amazonaws.com`
- `ec2messages.{region}.amazonaws.com`
- `s3.amazonaws.com` (for downloading SSM agent)

## Supported Operating Systems

- Ubuntu (18.04, 20.04, 22.04, 24.04)
- Debian (9, 10, 11, 12)
- RHEL (7, 8, 9)
- CentOS (7, 8)
- Rocky Linux (8, 9)
- AlmaLinux (8, 9)
- Amazon Linux (1, 2, 2023)

## Architecture Support

- x86_64 (AMD64)
- ARM64 (aarch64)

## Security Considerations

- **Credentials**: Never commit AWS credentials to version control
- **IAM Permissions**: Use least privilege principles
- **Activation Limits**: Set appropriate instance limits and expiration
- **Network Security**: Consider using VPC endpoints for SSM communication
- **SNS Topic**: Restrict who can publish to your SNS topic

## Maintenance

### Updating SSM Agent
SSM Agent auto-updates by default when managed by Systems Manager.

### Activation Expiration
Create new activations before expiration (default: 30 days) for new instances.

### Monitoring Best Practices
- Review CloudWatch alarms regularly
- Set up dashboard for fleet health
- Consider additional metrics (CPU, memory, disk)

## Cost Considerations

- **SSM**: No additional charges for on-premises instances
- **CloudWatch Alarms**: ~$0.10 per alarm per month
- **SNS**: ~$0.50 per million notifications
- **Data Transfer**: Minimal costs for heartbeat data

## Support

For issues related to:
- **This script**: Review troubleshooting section above
- **AWS Systems Manager**: [AWS Documentation](https://docs.aws.amazon.com/systems-manager/)
- **CloudWatch**: [CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/)

## License

This script is provided as-is for use with AWS Systems Manager hybrid activations.

## Changelog

### Version 1.0
- Initial release with SSM agent installation
- OS auto-detection
- IAM role creation
- Hybrid activation automation
- CloudWatch alarm integration
- Email notifications via SNS