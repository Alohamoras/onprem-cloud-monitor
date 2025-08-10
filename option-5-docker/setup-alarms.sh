#!/bin/bash
# Setup CloudWatch Alarms for Docker Container Monitor

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
AWS_REGION=${AWS_REGION:-"us-east-1"}
CONTAINER_NAME=${CONTAINER_NAME:-""}
SNS_TOPIC_ARN=${SNS_TOPIC_ARN:-""}
CLOUDWATCH_NAMESPACE=${CLOUDWATCH_NAMESPACE:-"ContainerMonitoring/Heartbeat"}

print_info "CloudWatch Alarms Setup for Container Monitor"
print_info "=============================================="

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install AWS CLI first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured. Please run 'aws configure'."
    exit 1
fi

# Get input if not provided via environment variables
if [ -z "$CONTAINER_NAME" ]; then
    echo -n "Enter container name (used in alarm naming): "
    read CONTAINER_NAME
fi

if [ -z "$SNS_TOPIC_ARN" ]; then
    echo ""
    print_info "Available SNS topics in region $AWS_REGION:"
    aws sns list-topics --region $AWS_REGION --query 'Topics[*].TopicArn' --output table 2>/dev/null || true
    echo ""
    echo -n "Enter SNS Topic ARN for notifications: "
    read SNS_TOPIC_ARN
fi

if [ -z "$CONTAINER_NAME" ] || [ -z "$SNS_TOPIC_ARN" ]; then
    print_error "Container name and SNS Topic ARN are required"
    exit 1
fi

print_info "Configuration:"
print_info "  Container Name: $CONTAINER_NAME"
print_info "  AWS Region: $AWS_REGION"
print_info "  CloudWatch Namespace: $CLOUDWATCH_NAMESPACE"
print_info "  SNS Topic: $SNS_TOPIC_ARN"
print_info ""

# Create Container Heartbeat Alarm
print_info "Creating container heartbeat alarm..."
HEARTBEAT_ALARM_NAME="Container-Heartbeat-Lost-${CONTAINER_NAME}"

aws cloudwatch put-metric-alarm \
    --alarm-name "$HEARTBEAT_ALARM_NAME" \
    --alarm-description "Container heartbeat lost for ${CONTAINER_NAME}" \
    --metric-name ContainerHeartbeat \
    --namespace "$CLOUDWATCH_NAMESPACE" \
    --statistic Sum \
    --period 600 \
    --threshold 0.5 \
    --comparison-operator LessThanThreshold \
    --datapoints-to-alarm 2 \
    --evaluation-periods 2 \
    --treat-missing-data breaching \
    --dimensions Name=ContainerName,Value="$CONTAINER_NAME" \
    --alarm-actions "$SNS_TOPIC_ARN" \
    --ok-actions "$SNS_TOPIC_ARN" \
    --region "$AWS_REGION"

if [ $? -eq 0 ]; then
    print_success "Created heartbeat alarm: $HEARTBEAT_ALARM_NAME"
else
    print_error "Failed to create heartbeat alarm"
    exit 1
fi

# Create Target Monitoring Alarm (if targets are being monitored)
print_info "Creating target monitoring alarm..."
TARGET_ALARM_NAME="Container-Target-Offline-${CONTAINER_NAME}"

aws cloudwatch put-metric-alarm \
    --alarm-name "$TARGET_ALARM_NAME" \
    --alarm-description "Monitored targets offline for ${CONTAINER_NAME}" \
    --metric-name TargetStatus \
    --namespace "$CLOUDWATCH_NAMESPACE" \
    --statistic Average \
    --period 300 \
    --threshold 0.5 \
    --comparison-operator LessThanThreshold \
    --datapoints-to-alarm 2 \
    --evaluation-periods 2 \
    --treat-missing-data notBreaching \
    --dimensions Name=ContainerName,Value="$CONTAINER_NAME" \
    --alarm-actions "$SNS_TOPIC_ARN" \
    --ok-actions "$SNS_TOPIC_ARN" \
    --region "$AWS_REGION" 2>/dev/null

if [ $? -eq 0 ]; then
    print_success "Created target monitoring alarm: $TARGET_ALARM_NAME"
else
    print_warning "Target monitoring alarm creation failed (this is normal if not monitoring targets)"
fi

# Create Fleet-Wide Alarm (optional)
echo ""
FLEET_RESPONSE=$(echo "y" | head -1)
read -p "Create fleet-wide alarm for ANY container failure? (y/N): " -t 10 FLEET_RESPONSE 2>/dev/null || FLEET_RESPONSE="n"

if [[ "$FLEET_RESPONSE" =~ ^[Yy]$ ]]; then
    print_info "Creating fleet-wide alarm..."
    FLEET_ALARM_NAME="Container-Fleet-AnyOffline"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$FLEET_ALARM_NAME" \
        --alarm-description "Any container heartbeat lost" \
        --metric-name ContainerHeartbeat \
        --namespace "$CLOUDWATCH_NAMESPACE" \
        --statistic Sum \
        --period 600 \
        --threshold 0.5 \
        --comparison-operator LessThanThreshold \
        --datapoints-to-alarm 2 \
        --evaluation-periods 2 \
        --treat-missing-data breaching \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --region "$AWS_REGION" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_success "Created fleet-wide alarm: $FLEET_ALARM_NAME"
    else
        print_warning "Fleet-wide alarm creation failed (may already exist)"
    fi
fi

# Test SNS notification
echo ""
read -p "Send test notification? (y/N): " -t 10 TEST_RESPONSE 2>/dev/null || TEST_RESPONSE="n"

if [[ "$TEST_RESPONSE" =~ ^[Yy]$ ]]; then
    print_info "Sending test notification..."
    TEST_MESSAGE="🧪 Test notification from Container Monitor setup for ${CONTAINER_NAME} at $(date)"
    
    aws sns publish \
        --topic-arn "$SNS_TOPIC_ARN" \
        --message "$TEST_MESSAGE" \
        --subject "Container Monitor Test" \
        --region "$AWS_REGION"
    
    if [ $? -eq 0 ]; then
        print_success "Test notification sent - check your email"
    else
        print_error "Failed to send test notification"
    fi
fi

# Summary
print_info ""
print_success "CloudWatch Alarms Setup Complete!"
print_info ""
print_info "Created alarms:"
print_info "  1. $HEARTBEAT_ALARM_NAME"
print_info "     - Triggers when container stops sending heartbeats"
print_info "     - Threshold: No heartbeat for 10 minutes"
print_info ""
print_info "  2. $TARGET_ALARM_NAME"
print_info "     - Triggers when monitored targets go offline"
print_info "     - Threshold: Targets offline for 5 minutes"
print_info ""

if [[ "$FLEET_RESPONSE" =~ ^[Yy]$ ]]; then
    print_info "  3. $FLEET_ALARM_NAME"
    print_info "     - Triggers when ANY container stops heartbeats"
    print_info ""
fi

print_info "Next steps:"
print_info "1. Start your container with:"
print_info "   docker-compose up -d"
print_info ""
print_info "2. Monitor alarms in CloudWatch console:"
print_info "   https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#alarmsV2:"
print_info ""
print_info "3. View metrics in CloudWatch:"
print_info "   Namespace: $CLOUDWATCH_NAMESPACE"
print_info ""
print_info "4. Test alerting by stopping the container:"
print_info "   docker stop onprem-monitor"
print_info "   (You should receive an alert within 10-15 minutes)"

# Save configuration for future reference
cat > alarm-config.txt << EOF
# CloudWatch Alarms Configuration
# Generated on $(date)

AWS_REGION=$AWS_REGION
CONTAINER_NAME=$CONTAINER_NAME
SNS_TOPIC_ARN=$SNS_TOPIC_ARN
CLOUDWATCH_NAMESPACE=$CLOUDWATCH_NAMESPACE

# Created Alarms:
# - $HEARTBEAT_ALARM_NAME
# - $TARGET_ALARM_NAME
EOF

print_info ""
print_info "Configuration saved to alarm-config.txt"