# Lambda Deployment Guide for On-Premises Monitor

## Overview

This guide covers deploying the on-premises monitoring solution using AWS Lambda instead of EC2. The Lambda approach offers serverless scalability, reduced operational overhead, and potentially lower costs for smaller deployments.

**Key Benefits of Lambda Approach:**
- ✅ **Serverless** - No EC2 instance to manage or patch
- ✅ **Cost-effective** - Pay only for execution time (~$1-16/month depending on network setup)
- ✅ **Auto-scaling** - Handles multiple concurrent executions if needed
- ✅ **Built-in monitoring** - CloudWatch integration and error handling

---

## Prerequisites

- AWS CLI configured with appropriate permissions
- VPC with connectivity to your on-premises devices (or public internet access)
- Basic understanding of Lambda and networking
- Python 3.13 runtime support in your region

---

## Step 1: Create IAM Role for Lambda

### Create IAM Policies

```bash
# 1. CloudWatch Metrics Policy
cat > lambda-cloudwatch-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:ListMetrics",
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# 2. VPC Access Policy (for Lambda in VPC - optional)
cat > lambda-vpc-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateNetworkInterface",
                "ec2:DeleteNetworkInterface",
                "ec2:DescribeNetworkInterfaces"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# 3. CloudWatch Logs Policy (for Lambda logging)
cat > lambda-logs-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:log-group:/aws/lambda/on-prem-monitor*"
        }
    ]
}
EOF

# Create the policies
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam create-policy \
    --policy-name OnPremLambdaCloudWatchPolicy \
    --policy-document file://lambda-cloudwatch-policy.json

aws iam create-policy \
    --policy-name OnPremLambdaVPCPolicy \
    --policy-document file://lambda-vpc-policy.json

aws iam create-policy \
    --policy-name OnPremLambdaLogsPolicy \
    --policy-document file://lambda-logs-policy.json
```

### Create IAM Role

```bash
# Create trust policy for Lambda
cat > lambda-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create the role
aws iam create-role \
    --role-name OnPremMonitorLambdaRole \
    --assume-role-policy-document file://lambda-trust-policy.json

# Attach policies to role
aws iam attach-role-policy \
    --role-name OnPremMonitorLambdaRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/OnPremLambdaCloudWatchPolicy

aws iam attach-role-policy \
    --role-name OnPremMonitorLambdaRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/OnPremLambdaLogsPolicy

# Only attach VPC policy if you need VPC access
aws iam attach-role-policy \
    --role-name OnPremMonitorLambdaRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/OnPremLambdaVPCPolicy
```

---

## Step 2: Create SNS Topic for Alerts

### Create SNS Topic

```bash
# Create SNS topic for alerts
aws sns create-topic \
    --name OnPrem-Monitor-Alerts \
    --region $(aws configure get region)

# Get the Topic ARN (save this for later steps)
SNS_TOPIC_ARN=$(aws sns describe-topics \
    --query 'Topics[?contains(TopicArn, `OnPrem-Monitor-Alerts`)].TopicArn' \
    --output text)

echo "SNS Topic ARN: $SNS_TOPIC_ARN"
```

### Subscribe Email to Topic

```bash
# Subscribe your email to the topic
aws sns subscribe \
    --topic-arn $SNS_TOPIC_ARN \
    --protocol email \
    --notification-endpoint your-email@example.com

echo "Check your email and confirm the subscription"
```

### Verify Subscription

```bash
# List subscriptions to verify
aws sns list-subscriptions-by-topic \
    --topic-arn $SNS_TOPIC_ARN

# Test the topic (optional)
aws sns publish \
    --topic-arn $SNS_TOPIC_ARN \
    --message "Test message from on-premises monitor setup" \
    --subject "Test Alert"
```

---

## Step 3: Prepare Lambda Function Code

### Configure Your Devices

The Lambda function uses environment variables for configuration, so you don't need to modify the code directly. You'll set these when creating the Lambda function:

- `TARGET_DEVICES`: Comma-separated list of IP addresses (e.g., "10.0.1.100,10.0.1.101")
- `TARGET_PORT`: Port to test (default: 8443)
- `TIMEOUT`: Connection timeout in seconds (default: 5)
- `CLOUDWATCH_NAMESPACE`: CloudWatch namespace (default: OnPrem/MultiDevice)

### Create Deployment Package

```bash
# Create deployment directory
mkdir on-prem-lambda-deploy
cd on-prem-lambda-deploy

# Copy the lambda function (assuming you're in the project root)
cp option-2-serverless/on-prem-monitor.py lambda_function.py

# Create deployment package (no external dependencies needed)
zip on-prem-monitor.zip lambda_function.py

echo "Deployment package created: on-prem-monitor.zip"
```

---

## Step 4: Network Configuration (Optional)

### Option A: Private Subnet with NAT Gateway (Recommended)

**Best for:** Production environments with existing NAT infrastructure  
**Cost:** ~$50/month (mainly NAT Gateway costs)

```bash
# Identify your private subnet and security group
PRIVATE_SUBNET_ID="subnet-YOUR_PRIVATE_SUBNET"
VPC_ID="vpc-YOUR_VPC_ID"

# Create security group for Lambda
aws ec2 create-security-group \
    --group-name SnowballLambda-SG \
    --description "Snowball Monitor Lambda Security Group" \
    --vpc-id $VPC_ID

LAMBDA_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=SnowballLambda-SG" \
    --query 'SecurityGroups[0].GroupId' --output text)

# Lambda doesn't need inbound rules, only outbound to Snowball devices and AWS services
echo "Lambda Security Group created: $LAMBDA_SG_ID"
echo "Default outbound rules allow all traffic - this is needed for AWS API calls"
```

### Option B: Private Subnet with VPC Endpoints

**Best for:** High-security environments  
**Cost:** ~$20/month (VPC endpoints)

```bash
# Create VPC endpoints for AWS services (if not already existing)
# See Advanced-Networking-Guide.md for detailed VPC endpoint setup

# Required endpoints for Lambda:
# - CloudWatch (monitoring.REGION.amazonaws.com)
# - Lambda service (lambda.REGION.amazonaws.com) 
# - CloudWatch Logs (logs.REGION.amazonaws.com)

# Create endpoints using commands from Advanced-Networking-Guide.md
```

**Note:** If your devices are accessible via public internet, you can skip the VPC configuration entirely and deploy Lambda without VPC settings.

---

## Step 5: Deploy Lambda Function

### Create Lambda Function

```bash
# Get your role ARN
ROLE_ARN=$(aws iam get-role --role-name OnPremMonitorLambdaRole --query 'Role.Arn' --output text)

# Set your device configuration
TARGET_DEVICES="10.0.1.100,10.0.1.101"  # Replace with your device IPs
TARGET_PORT="8443"                       # Replace with your device port
TIMEOUT="5"                              # Connection timeout in seconds

# Deploy Lambda function (without VPC for simplicity)
aws lambda create-function \
    --function-name on-prem-monitor \
    --runtime python3.13 \
    --role $ROLE_ARN \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://on-prem-monitor.zip \
    --timeout 60 \
    --memory-size 128 \
    --description "On-premises device connectivity monitoring" \
    --environment Variables="{TARGET_DEVICES=$TARGET_DEVICES,TARGET_PORT=$TARGET_PORT,TIMEOUT=$TIMEOUT}"

echo "Lambda function created successfully"
```

### Configure Environment Variables (Optional)

```bash
# If you want to make configuration more flexible
aws lambda update-function-configuration \
    --function-name snowball-monitor \
    --environment Variables='{
        "SNOWBALL_DEVICES":"10.0.1.100,10.0.1.101",
        "SNOWBALL_PORT":"8443",
        "TIMEOUT":"5"
    }'
```

---

## Step 6: Set Up EventBridge Scheduling

### Create EventBridge Rule

```bash
# Create rule for every 2 minutes
aws events put-rule \
    --name on-prem-monitor-schedule \
    --schedule-expression "rate(2 minutes)" \
    --description "Trigger on-premises monitoring every 2 minutes"

# Get Lambda function ARN
LAMBDA_ARN=$(aws lambda get-function --function-name on-prem-monitor --query 'Configuration.FunctionArn' --output text)

# Add Lambda as target
aws events put-targets \
    --rule on-prem-monitor-schedule \
    --targets "Id"="1","Arn"="$LAMBDA_ARN"

# Grant EventBridge permission to invoke Lambda
aws lambda add-permission \
    --function-name on-prem-monitor \
    --statement-id allow-eventbridge \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:$(aws configure get region):${ACCOUNT_ID}:rule/on-prem-monitor-schedule

echo "EventBridge rule created and configured"
```

### Alternative Schedule Options

```bash
# Every 5 minutes (lighter load)
aws events put-rule \
    --name snowball-monitor-schedule \
    --schedule-expression "rate(5 minutes)"

# Every minute (maximum frequency)
aws events put-rule \
    --name snowball-monitor-schedule \
    --schedule-expression "rate(1 minute)"

# Business hours only (9 AM to 6 PM UTC, Monday-Friday)
aws events put-rule \
    --name snowball-monitor-schedule \
    --schedule-expression "cron(*/2 9-18 ? * MON-FRI *)"
```

---

## Step 7: Create CloudWatch Alarms

Use the same alarm configuration from the main deployment guide:

```bash
# Use the SNS topic ARN from Step 2
# SNS_TOPIC_ARN should already be set from earlier

# 1. OVERALL HEALTH ALARM: Triggers when ANY device goes offline
aws cloudwatch put-metric-alarm \
    --alarm-name "OnPrem-Lambda-AnyOffline" \
    --alarm-description "Alert when any on-premises device goes offline (Lambda)" \
    --metric-name TotalOffline \
    --namespace OnPrem/MultiDevice \
    --statistic Maximum \
    --period 300 \
    --evaluation-periods 1 \
    --datapoints-to-alarm 1 \
    --threshold 0.5 \
    --comparison-operator GreaterThanThreshold \
    --alarm-actions $SNS_TOPIC_ARN \
    --ok-actions $SNS_TOPIC_ARN \
    --treat-missing-data breaching

# 2. LAMBDA HEALTH ALARM: Triggers when Lambda stops running
aws cloudwatch put-metric-alarm \
    --alarm-name "OnPrem-Lambda-NotReporting" \
    --alarm-description "Alert when Lambda monitoring stops reporting" \
    --metric-name TotalDevices \
    --namespace OnPrem/MultiDevice \
    --statistic SampleCount \
    --period 900 \
    --evaluation-periods 2 \
    --threshold 1 \
    --comparison-operator LessThanThreshold \
    --treat-missing-data breaching \
    --alarm-actions $SNS_TOPIC_ARN

# 3. LAMBDA ERROR ALARM: Triggers on Lambda execution errors
aws cloudwatch put-metric-alarm \
    --alarm-name "OnPrem-Lambda-Errors" \
    --alarm-description "Alert on Lambda function errors" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --evaluation-periods 1 \
    --threshold 0.5 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=FunctionName,Value=on-prem-monitor \
    --alarm-actions $SNS_TOPIC_ARN
```

---

## Step 7: Testing and Validation

### Test Lambda Function Manually

```bash
# Test function execution
aws lambda invoke \
    --function-name snowball-monitor \
    --payload '{}' \
    response.json

# View response
cat response.json

# Check if function succeeded
if [[ $? -eq 0 ]]; then
    echo "✅ Lambda function executed successfully"
else
    echo "❌ Lambda function failed"
fi
```

### Test EventBridge Integration

```bash
# Manually trigger EventBridge rule (for testing)
aws events put-events \
    --entries Source=test,DetailType="Manual Test",Detail='{}'

# Check CloudWatch Logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/snowball-monitor \
    --order-by LastEventTime \
    --descending

# View latest log stream
LATEST_STREAM=$(aws logs describe-log-streams \
    --log-group-name /aws/lambda/snowball-monitor \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text)

aws logs get-log-events \
    --log-group-name /aws/lambda/snowball-monitor \
    --log-stream-name $LATEST_STREAM
```

### Validate Metrics in CloudWatch

```bash
# Check if metrics are being sent
aws cloudwatch list-metrics \
    --namespace Snowball/MultiDevice

# Get recent metric data
aws cloudwatch get-metric-statistics \
    --namespace Snowball/MultiDevice \
    --metric-name TotalOnline \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Maximum
```

---

## Step 8: Monitoring and Troubleshooting

### Monitor Lambda Performance

```bash
# Check Lambda metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value=snowball-monitor \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average,Maximum

# Check error rates
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Errors \
    --dimensions Name=FunctionName,Value=snowball-monitor \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

### Real-time Log Monitoring

```bash
# Stream Lambda logs in real-time (requires AWS SAM CLI or similar)
# Alternative: Use AWS Console CloudWatch Logs

# Manual log checking
aws logs filter-log-events \
    --log-group-name /aws/lambda/snowball-monitor \
    --start-time $(date -d '1 hour ago' +%s)000
```

### Common Troubleshooting

```bash
# 1. Check VPC configuration
aws lambda get-function-configuration \
    --function-name snowball-monitor \
    --query 'VpcConfig'

# 2. Check security group rules
aws ec2 describe-security-groups --group-ids $LAMBDA_SG_ID

# 3. Test network connectivity from within VPC
# (Deploy test Lambda with network debugging code)

# 4. Check EventBridge rule status
aws events describe-rule --name snowball-monitor-schedule

# 5. List recent Lambda invocations
aws lambda get-function \
    --function-name snowball-monitor \
    --query 'Configuration.[LastModified,LastUpdateStatus]'
```

---

## Step 9: Maintenance and Updates

### Update Lambda Function Code

```bash
# After modifying snowball-monitor-lambda.py
zip snowball-monitor-lambda.zip lambda_function.py

aws lambda update-function-code \
    --function-name snowball-monitor \
    --zip-file fileb://snowball-monitor-lambda.zip

echo "Lambda function updated"
```

### Update Configuration

```bash
# Add/remove Snowball devices by updating environment variables
aws lambda update-function-configuration \
    --function-name snowball-monitor \
    --environment Variables='{
        "SNOWBALL_DEVICES":"10.0.1.100,10.0.1.101,10.0.1.102",
        "SNOWBALL_PORT":"8443",
        "TIMEOUT":"5"
    }'
```

### Scale Up Resources (if needed)

```bash
# Increase memory if monitoring many devices
aws lambda update-function-configuration \
    --function-name snowball-monitor \
    --memory-size 256

# Increase timeout if needed (max 15 minutes)
aws lambda update-function-configuration \
    --function-name snowball-monitor \
    --timeout 120
```

---


## Cost Breakdown

### Monthly Cost Estimate for Lambda Snowball Monitor

| Component | Cost | Notes |
|-----------|------|-------|
| **Lambda Execution** | ~$0.72 | 21,600 executions/month (every 2 min) |
| **Lambda Requests** | ~$0.004 | 21,600 requests × $0.0000002 |
| **CloudWatch Logs** | ~$0.50 | Function logs and retention |
| **CloudWatch Metrics** | ~$0.30 | Custom metrics storage |
| **EventBridge Rules** | Free | Standard scheduling rules |
| **VPC NAT Gateway** | ~$45.00 | $32.40 base + $0.045/GB data |
| **OR VPC Endpoints** | ~$15.00 | $7.20/endpoint × 2 endpoints |
| **Data Transfer** | ~$0.10 | Minimal inter-AZ and internet |

### Total Monthly Costs

| Deployment Option | Total Cost |
|-------------------|------------|
| **Lambda + NAT Gateway** | **~$46.50** |
| **Lambda + VPC Endpoints** | **~$16.50** |

### Cost Scaling by Device Count

| Devices | Lambda Execution | Total (NAT) | Total (VPC Endpoints) |
|---------|------------------|-------------|----------------------|
| 1-5 devices | ~$0.72 | ~$46.50 | ~$16.50 |
| 6-10 devices | ~$1.00 | ~$46.80 | ~$16.80 |
| 11-20 devices | ~$1.50 | ~$47.30 | ~$17.30 |

### Key Cost Notes

- **Lambda costs scale linearly** with device count and execution time
- **Network costs dominate** - NAT Gateway vs VPC Endpoints is the main cost driver
- **Minimal data transfer** - each check is <1KB of data
- **CloudWatch costs** are predictable and low for this use case
- **No idle costs** - only pay when Lambda executes
- **Free tier eligible** - first 1M Lambda requests/month are free

### Annual Cost Summary
- **With NAT Gateway**: ~$558/year
- **With VPC Endpoints**: ~$198/year
- **Lambda execution only**: ~$8.64/year



---

## Security Best Practices

### Network Security
- **Use least-privilege security groups** - only allow required outbound traffic
- **Enable VPC Flow Logs** for network monitoring
- **Regular security group audits** - remove unused rules

### Function Security
- **Enable AWS X-Ray tracing** for debugging
- **Use AWS Secrets Manager** for sensitive configuration
- **Regular function updates** - keep runtime current

### Access Control
- **Minimal IAM permissions** - only CloudWatch metrics access
- **Use AWS CloudTrail** to audit all Lambda invocations
- **Regular access reviews** - ensure only authorized access

---

## Next Steps

1. **Monitor the logs** to ensure everything is working
2. **Test the alerting** by blocking access to a Snowball device
3. **Set up CloudWatch dashboards** for visualization
4. **Consider automation** with Terraform or CloudFormation
5. **Review costs** after one month of operation

This Lambda deployment offers a serverless, cost-effective alternative to the EC2 approach while maintaining the same monitoring capabilities and alarm structure.