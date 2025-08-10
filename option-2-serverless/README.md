# Lambda Serverless Monitoring (Option 2)

A serverless approach to monitoring on-premises devices using AWS Lambda, EventBridge, and CloudWatch.

## Quick Start (5 minutes)

### Prerequisites
- AWS CLI configured with appropriate permissions
- Email address for alerts

### One-Command Deployment

```bash
# Set your configuration
export TARGET_DEVICES="10.0.1.100,10.0.1.101"  # Your device IPs
export TARGET_PORT="8443"                       # Your device port  
export EMAIL_ADDRESS="your-email@example.com"   # Your email for alerts

# Deploy everything
./deploy.sh
```

That's it! The script will:
- Create all necessary AWS resources
- Deploy the Lambda function
- Set up monitoring and alerts
- Test the deployment

### Verify Deployment

```bash
./test-deployment.sh
```

## Key Features

- **Serverless**: No servers to manage or patch
- **Cost-effective**: ~$1-16/month depending on network setup
- **Auto-scaling**: Handles multiple devices automatically
- **Smart alerting**: Only notifies when status changes
- **Easy deployment**: Single script setup

## How It Works

```
EventBridge (every 2 min) → Lambda Function → Test Device Connectivity
                                    ↓
CloudWatch Metrics ← Device Status (1=Online, 0=Offline)
        ↓
CloudWatch Alarms → SNS Topic → Email/SMS Alerts
```

## Configuration

The Lambda function uses environment variables:

- `TARGET_DEVICES`: Comma-separated device IPs (e.g., "10.0.1.100,10.0.1.101")
- `TARGET_PORT`: Port to test (default: 8443)
- `TIMEOUT`: Connection timeout in seconds (default: 5)
- `CLOUDWATCH_NAMESPACE`: Metrics namespace (default: OnPrem/MultiDevice)

## Files

- `deploy.sh` - Automated deployment script
- `test-deployment.sh` - Deployment verification script
- `on-prem-monitor.py` - Lambda function code
- `lambda-deployment-guide.md` - Detailed manual deployment guide
- `network-test.py` - Network connectivity testing utility

## Cost Estimate

| Component | Monthly Cost |
|-----------|--------------|
| Lambda execution | ~$0.72 |
| CloudWatch metrics | ~$0.30 |
| CloudWatch logs | ~$0.50 |
| SNS notifications | ~$0.10 |
| **Total** | **~$1.62** |

*Note: Add ~$45/month if you need VPC NAT Gateway for private network access*

## Troubleshooting

### Common Issues

**Lambda function fails to connect to devices:**
- Check if devices are accessible from the internet (Lambda runs outside your VPC by default)
- For private networks, see the VPC configuration section in the deployment guide

**No metrics appearing:**
- Wait 5-10 minutes after first deployment
- Check Lambda logs: `/aws/lambda/on-prem-monitor`
- Verify EventBridge rule is enabled

**Not receiving email alerts:**
- Check your email and confirm SNS subscription
- Test SNS topic: `aws sns publish --topic-arn <topic-arn> --message "test"`

### Getting Help

1. Run `./test-deployment.sh` to diagnose issues
2. Check CloudWatch Logs for Lambda execution details
3. Verify your device IPs and ports are correct
4. See the detailed deployment guide for advanced configuration

## Advanced Configuration

For advanced networking, VPC configuration, or custom alerting, see the [detailed deployment guide](lambda-deployment-guide.md).

## Cleanup

To remove all resources:

```bash
# Delete Lambda function
aws lambda delete-function --function-name on-prem-monitor

# Delete EventBridge rule
aws events remove-targets --rule on-prem-monitor-schedule --ids 1
aws events delete-rule --name on-prem-monitor-schedule

# Delete CloudWatch alarms
aws cloudwatch delete-alarms --alarm-names OnPrem-Lambda-AnyOffline OnPrem-Lambda-NotReporting OnPrem-Lambda-Errors

# Delete SNS topic (optional)
aws sns delete-topic --topic-arn arn:aws:sns:$(aws configure get region):$(aws sts get-caller-identity --query Account --output text):OnPrem-Monitor-Alerts

# Delete IAM role and policies (optional)
aws iam detach-role-policy --role-name OnPremMonitorLambdaRole --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/OnPremLambdaCloudWatchPolicy
aws iam detach-role-policy --role-name OnPremMonitorLambdaRole --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/OnPremLambdaLogsPolicy
aws iam delete-role --role-name OnPremMonitorLambdaRole
aws iam delete-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/OnPremLambdaCloudWatchPolicy
aws iam delete-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/OnPremLambdaLogsPolicy
```