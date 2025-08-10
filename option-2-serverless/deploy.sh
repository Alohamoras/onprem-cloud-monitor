#!/bin/bash

# On-Premises Monitor Lambda Deployment Script
# This script automates the complete deployment of the Lambda-based monitoring solution

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Modify these values
TARGET_DEVICES="${TARGET_DEVICES:-10.0.1.100,10.0.1.101}"
TARGET_PORT="${TARGET_PORT:-8443}"
TIMEOUT="${TIMEOUT:-5}"
EMAIL_ADDRESS="${EMAIL_ADDRESS:-}"
AWS_REGION="${AWS_REGION:-$(aws configure get region)}"

# Derived values
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
FUNCTION_NAME="on-prem-monitor"
ROLE_NAME="OnPremMonitorLambdaRole"
SNS_TOPIC_NAME="OnPrem-Monitor-Alerts"

echo -e "${BLUE}=== On-Premises Monitor Lambda Deployment ===${NC}"
echo "Target Devices: $TARGET_DEVICES"
echo "Target Port: $TARGET_PORT"
echo "Timeout: $TIMEOUT seconds"
echo "AWS Region: $AWS_REGION"
echo "AWS Account: $ACCOUNT_ID"
echo ""

# Validation
if [[ -z "$ACCOUNT_ID" ]]; then
    echo -e "${RED}Error: Unable to get AWS account ID. Please check your AWS credentials.${NC}"
    exit 1
fi

if [[ -z "$EMAIL_ADDRESS" ]]; then
    echo -e "${YELLOW}Warning: EMAIL_ADDRESS not set. You'll need to subscribe to SNS manually.${NC}"
    echo "Set EMAIL_ADDRESS environment variable to auto-subscribe to alerts."
    echo ""
fi

# Function to check if AWS resource exists
check_resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local check_command=$3
    
    if eval "$check_command" >/dev/null 2>&1; then
        echo -e "${YELLOW}$resource_type '$resource_name' already exists, skipping creation${NC}"
        return 0
    else
        return 1
    fi
}

# Step 1: Create IAM Policies
echo -e "${BLUE}Step 1: Creating IAM policies...${NC}"

# CloudWatch policy
if ! check_resource_exists "IAM Policy" "OnPremLambdaCloudWatchPolicy" "aws iam get-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/OnPremLambdaCloudWatchPolicy"; then
    cat > /tmp/lambda-cloudwatch-policy.json << 'EOF'
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

    aws iam create-policy \
        --policy-name OnPremLambdaCloudWatchPolicy \
        --policy-document file:///tmp/lambda-cloudwatch-policy.json
    echo -e "${GREEN}Created CloudWatch policy${NC}"
fi

# Logs policy
if ! check_resource_exists "IAM Policy" "OnPremLambdaLogsPolicy" "aws iam get-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/OnPremLambdaLogsPolicy"; then
    cat > /tmp/lambda-logs-policy.json << 'EOF'
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

    aws iam create-policy \
        --policy-name OnPremLambdaLogsPolicy \
        --policy-document file:///tmp/lambda-logs-policy.json
    echo -e "${GREEN}Created Logs policy${NC}"
fi

# Step 2: Create IAM Role
echo -e "${BLUE}Step 2: Creating IAM role...${NC}"

if ! check_resource_exists "IAM Role" "$ROLE_NAME" "aws iam get-role --role-name $ROLE_NAME"; then
    cat > /tmp/lambda-trust-policy.json << 'EOF'
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

    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json
    
    # Wait a moment for role to be created
    sleep 5
    echo -e "${GREEN}Created IAM role${NC}"
fi

# Attach policies to role
echo "Attaching policies to role..."
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/OnPremLambdaCloudWatchPolicy 2>/dev/null || true

aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/OnPremLambdaLogsPolicy 2>/dev/null || true

# Step 3: Create SNS Topic
echo -e "${BLUE}Step 3: Creating SNS topic...${NC}"

if ! check_resource_exists "SNS Topic" "$SNS_TOPIC_NAME" "aws sns get-topic-attributes --topic-arn arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${SNS_TOPIC_NAME}"; then
    aws sns create-topic --name $SNS_TOPIC_NAME --region $AWS_REGION
    echo -e "${GREEN}Created SNS topic${NC}"
fi

SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${SNS_TOPIC_NAME}"

# Subscribe email if provided
if [[ -n "$EMAIL_ADDRESS" ]]; then
    echo "Subscribing $EMAIL_ADDRESS to SNS topic..."
    aws sns subscribe \
        --topic-arn $SNS_TOPIC_ARN \
        --protocol email \
        --notification-endpoint $EMAIL_ADDRESS
    echo -e "${YELLOW}Check your email and confirm the subscription${NC}"
fi

# Step 4: Create Lambda deployment package
echo -e "${BLUE}Step 4: Creating Lambda deployment package...${NC}"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# Copy the Lambda function
if [[ -f "$(dirname $0)/on-prem-monitor.py" ]]; then
    cp "$(dirname $0)/on-prem-monitor.py" lambda_function.py
else
    echo -e "${RED}Error: on-prem-monitor.py not found in script directory${NC}"
    exit 1
fi

# Create deployment package
zip on-prem-monitor.zip lambda_function.py
echo -e "${GREEN}Created deployment package${NC}"

# Step 5: Deploy Lambda function
echo -e "${BLUE}Step 5: Deploying Lambda function...${NC}"

ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)

if check_resource_exists "Lambda Function" "$FUNCTION_NAME" "aws lambda get-function --function-name $FUNCTION_NAME"; then
    echo "Updating existing Lambda function..."
    aws lambda update-function-code \
        --function-name $FUNCTION_NAME \
        --zip-file fileb://on-prem-monitor.zip
    
    aws lambda update-function-configuration \
        --function-name $FUNCTION_NAME \
        --environment Variables="{TARGET_DEVICES=$TARGET_DEVICES,TARGET_PORT=$TARGET_PORT,TIMEOUT=$TIMEOUT}"
else
    echo "Creating new Lambda function..."
    aws lambda create-function \
        --function-name $FUNCTION_NAME \
        --runtime python3.13 \
        --role $ROLE_ARN \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://on-prem-monitor.zip \
        --timeout 60 \
        --memory-size 128 \
        --description "On-premises device connectivity monitoring" \
        --environment Variables="{TARGET_DEVICES=$TARGET_DEVICES,TARGET_PORT=$TARGET_PORT,TIMEOUT=$TIMEOUT}"
fi

echo -e "${GREEN}Lambda function deployed${NC}"

# Step 6: Create EventBridge schedule
echo -e "${BLUE}Step 6: Creating EventBridge schedule...${NC}"

SCHEDULE_NAME="on-prem-monitor-schedule"

if ! check_resource_exists "EventBridge Rule" "$SCHEDULE_NAME" "aws events describe-rule --name $SCHEDULE_NAME"; then
    aws events put-rule \
        --name $SCHEDULE_NAME \
        --schedule-expression "rate(2 minutes)" \
        --description "Trigger on-premises monitoring every 2 minutes"
    echo -e "${GREEN}Created EventBridge rule${NC}"
fi

# Add Lambda as target
LAMBDA_ARN=$(aws lambda get-function --function-name $FUNCTION_NAME --query 'Configuration.FunctionArn' --output text)

aws events put-targets \
    --rule $SCHEDULE_NAME \
    --targets "Id"="1","Arn"="$LAMBDA_ARN" 2>/dev/null || true

# Grant EventBridge permission to invoke Lambda
aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --statement-id allow-eventbridge \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:${AWS_REGION}:${ACCOUNT_ID}:rule/${SCHEDULE_NAME} 2>/dev/null || true

echo -e "${GREEN}EventBridge schedule configured${NC}"

# Step 7: Create CloudWatch Alarms
echo -e "${BLUE}Step 7: Creating CloudWatch alarms...${NC}"

# Overall health alarm
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

# Lambda health alarm
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

# Lambda error alarm
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
    --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
    --alarm-actions $SNS_TOPIC_ARN

echo -e "${GREEN}CloudWatch alarms created${NC}"

# Cleanup
cd - >/dev/null
rm -rf $TEMP_DIR
rm -f /tmp/lambda-*.json

# Step 8: Test deployment
echo -e "${BLUE}Step 8: Testing deployment...${NC}"

echo "Invoking Lambda function for initial test..."
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    /tmp/lambda-response.json

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Lambda function test successful${NC}"
    echo "Response:"
    cat /tmp/lambda-response.json | python3 -m json.tool 2>/dev/null || cat /tmp/lambda-response.json
    rm -f /tmp/lambda-response.json
else
    echo -e "${RED}Lambda function test failed${NC}"
fi

echo ""
echo -e "${GREEN}=== Deployment Complete! ===${NC}"
echo ""
echo "Resources created:"
echo "- Lambda Function: $FUNCTION_NAME"
echo "- IAM Role: $ROLE_NAME"
echo "- SNS Topic: $SNS_TOPIC_ARN"
echo "- EventBridge Rule: $SCHEDULE_NAME (runs every 2 minutes)"
echo "- CloudWatch Alarms: OnPrem-Lambda-AnyOffline, OnPrem-Lambda-NotReporting, OnPrem-Lambda-Errors"
echo ""
echo "Next steps:"
echo "1. Confirm your email subscription if you provided EMAIL_ADDRESS"
echo "2. Wait 5-10 minutes for initial metrics to appear"
echo "3. Check CloudWatch Logs: /aws/lambda/$FUNCTION_NAME"
echo "4. Monitor CloudWatch Metrics: OnPrem/MultiDevice namespace"
echo ""
echo "To test an alert, temporarily block access to one of your devices."
echo ""
echo -e "${BLUE}Monitoring is now active!${NC}"