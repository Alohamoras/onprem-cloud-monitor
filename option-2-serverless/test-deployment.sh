#!/bin/bash

# Test script for Lambda deployment
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FUNCTION_NAME="on-prem-monitor"
AWS_REGION="${AWS_REGION:-$(aws configure get region)}"

echo -e "${BLUE}=== Testing Lambda Deployment ===${NC}"

# Test 1: Check if Lambda function exists and is configured correctly
echo -e "${BLUE}Test 1: Lambda function configuration${NC}"
if aws lambda get-function --function-name $FUNCTION_NAME >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Lambda function exists${NC}"
    
    # Get function details
    RUNTIME=$(aws lambda get-function-configuration --function-name $FUNCTION_NAME --query 'Runtime' --output text)
    TIMEOUT=$(aws lambda get-function-configuration --function-name $FUNCTION_NAME --query 'Timeout' --output text)
    MEMORY=$(aws lambda get-function-configuration --function-name $FUNCTION_NAME --query 'MemorySize' --output text)
    
    echo "  Runtime: $RUNTIME"
    echo "  Timeout: ${TIMEOUT}s"
    echo "  Memory: ${MEMORY}MB"
    
    # Check environment variables
    TARGET_DEVICES=$(aws lambda get-function-configuration --function-name $FUNCTION_NAME --query 'Environment.Variables.TARGET_DEVICES' --output text 2>/dev/null || echo "Not set")
    echo "  Target Devices: $TARGET_DEVICES"
else
    echo -e "${RED}✗ Lambda function not found${NC}"
    exit 1
fi

# Test 2: Invoke Lambda function
echo -e "${BLUE}Test 2: Lambda function execution${NC}"
echo "Invoking Lambda function..."

aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    /tmp/test-response.json

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Lambda invocation successful${NC}"
    
    # Parse response
    if command -v jq >/dev/null 2>&1; then
        echo "Response summary:"
        jq -r '.body | fromjson | "Total devices: \(.total_devices), Online: \(.online_count), Offline: \(.offline_count)"' /tmp/test-response.json 2>/dev/null || echo "Could not parse response"
    else
        echo "Response (install jq for better formatting):"
        cat /tmp/test-response.json
    fi
else
    echo -e "${RED}✗ Lambda invocation failed${NC}"
fi

# Test 3: Check EventBridge rule
echo -e "${BLUE}Test 3: EventBridge schedule${NC}"
SCHEDULE_NAME="on-prem-monitor-schedule"

if aws events describe-rule --name $SCHEDULE_NAME >/dev/null 2>&1; then
    echo -e "${GREEN}✓ EventBridge rule exists${NC}"
    
    STATE=$(aws events describe-rule --name $SCHEDULE_NAME --query 'State' --output text)
    SCHEDULE=$(aws events describe-rule --name $SCHEDULE_NAME --query 'ScheduleExpression' --output text)
    
    echo "  State: $STATE"
    echo "  Schedule: $SCHEDULE"
    
    # Check targets
    TARGET_COUNT=$(aws events list-targets-by-rule --rule $SCHEDULE_NAME --query 'length(Targets)' --output text)
    echo "  Targets: $TARGET_COUNT"
else
    echo -e "${RED}✗ EventBridge rule not found${NC}"
fi

# Test 4: Check CloudWatch alarms
echo -e "${BLUE}Test 4: CloudWatch alarms${NC}"

ALARMS=("OnPrem-Lambda-AnyOffline" "OnPrem-Lambda-NotReporting" "OnPrem-Lambda-Errors")
for alarm in "${ALARMS[@]}"; do
    if aws cloudwatch describe-alarms --alarm-names $alarm >/dev/null 2>&1; then
        STATE=$(aws cloudwatch describe-alarms --alarm-names $alarm --query 'MetricAlarms[0].StateValue' --output text)
        echo -e "${GREEN}✓ $alarm ($STATE)${NC}"
    else
        echo -e "${RED}✗ $alarm not found${NC}"
    fi
done

# Test 5: Check SNS topic
echo -e "${BLUE}Test 5: SNS topic and subscriptions${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:OnPrem-Monitor-Alerts"

if aws sns get-topic-attributes --topic-arn $SNS_TOPIC_ARN >/dev/null 2>&1; then
    echo -e "${GREEN}✓ SNS topic exists${NC}"
    
    # Check subscriptions
    SUB_COUNT=$(aws sns list-subscriptions-by-topic --topic-arn $SNS_TOPIC_ARN --query 'length(Subscriptions)' --output text)
    echo "  Subscriptions: $SUB_COUNT"
    
    if [[ $SUB_COUNT -gt 0 ]]; then
        echo "  Subscription details:"
        aws sns list-subscriptions-by-topic --topic-arn $SNS_TOPIC_ARN --query 'Subscriptions[*].[Protocol,Endpoint,SubscriptionArn]' --output table
    fi
else
    echo -e "${RED}✗ SNS topic not found${NC}"
fi

# Test 6: Check recent Lambda logs
echo -e "${BLUE}Test 6: Recent Lambda logs${NC}"
LOG_GROUP="/aws/lambda/$FUNCTION_NAME"

if aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Log group exists${NC}"
    
    # Get latest log stream
    LATEST_STREAM=$(aws logs describe-log-streams \
        --log-group-name $LOG_GROUP \
        --order-by LastEventTime \
        --descending \
        --max-items 1 \
        --query 'logStreams[0].logStreamName' \
        --output text 2>/dev/null)
    
    if [[ "$LATEST_STREAM" != "None" && -n "$LATEST_STREAM" ]]; then
        echo "  Latest log stream: $LATEST_STREAM"
        echo "  Recent log entries:"
        aws logs get-log-events \
            --log-group-name $LOG_GROUP \
            --log-stream-name $LATEST_STREAM \
            --limit 5 \
            --query 'events[*].message' \
            --output text | tail -5
    else
        echo -e "${YELLOW}  No log streams found yet (function may not have run)${NC}"
    fi
else
    echo -e "${RED}✗ Log group not found${NC}"
fi

# Test 7: Check CloudWatch metrics
echo -e "${BLUE}Test 7: CloudWatch metrics${NC}"
NAMESPACE="OnPrem/MultiDevice"

# Check if metrics exist
METRICS=$(aws cloudwatch list-metrics --namespace $NAMESPACE --query 'length(Metrics)' --output text 2>/dev/null || echo "0")

if [[ $METRICS -gt 0 ]]; then
    echo -e "${GREEN}✓ Found $METRICS metrics in $NAMESPACE namespace${NC}"
    
    # List metric names
    echo "  Available metrics:"
    aws cloudwatch list-metrics --namespace $NAMESPACE --query 'Metrics[*].MetricName' --output text | tr '\t' '\n' | sort | uniq
else
    echo -e "${YELLOW}  No metrics found yet (may take a few minutes after first run)${NC}"
fi

# Cleanup
rm -f /tmp/test-response.json

echo ""
echo -e "${BLUE}=== Test Summary ===${NC}"
echo "If all tests show ✓, your deployment is working correctly."
echo "If you see ✗ or warnings, check the deployment guide for troubleshooting."
echo ""
echo "Next steps:"
echo "1. Wait 5-10 minutes for metrics to populate"
echo "2. Test an alert by blocking access to one of your devices"
echo "3. Check your email for alert notifications"
echo ""
echo -e "${GREEN}Testing complete!${NC}"