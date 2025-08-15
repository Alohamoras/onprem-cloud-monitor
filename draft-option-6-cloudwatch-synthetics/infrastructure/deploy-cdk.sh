#!/bin/bash

# CDK deployment script for CloudWatch Synthetics Canary Monitoring

set -e

# Default values
STACK_NAME="CanaryInfrastructureStack"
ENVIRONMENT="dev"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --stack-name)
      STACK_NAME="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --vpc-id)
      VPC_ID="$2"
      shift 2
      ;;
    --subnet-ids)
      SUBNET_IDS="$2"
      shift 2
      ;;
    --notification-email)
      NOTIFICATION_EMAIL="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  --stack-name NAME           CDK stack name (default: CanaryInfrastructureStack)"
      echo "  --environment ENV           Environment (dev/prod) (default: dev)"
      echo "  --vpc-id VPC_ID            VPC ID for canary deployment"
      echo "  --subnet-ids SUBNET_IDS    Comma-separated subnet IDs"
      echo "  --notification-email EMAIL Email for alarm notifications"
      echo "  --help                     Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo "Deploying CloudWatch Synthetics Canary Monitoring with CDK..."
echo "Stack Name: $STACK_NAME"
echo "Environment: $ENVIRONMENT"

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    echo "Error: AWS CDK is not installed. Please install it first:"
    echo "npm install -g aws-cdk"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed. Please install it first."
    exit 1
fi

# Navigate to CDK directory
cd cdk

# Install dependencies
echo "Installing CDK dependencies..."
npm install

# Set environment variables if provided
if [ ! -z "$VPC_ID" ]; then
    export VPC_ID=$VPC_ID
fi

if [ ! -z "$SUBNET_IDS" ]; then
    export SUBNET_IDS=$SUBNET_IDS
fi

if [ ! -z "$NOTIFICATION_EMAIL" ]; then
    export NOTIFICATION_EMAIL=$NOTIFICATION_EMAIL
fi

# Set environment-specific defaults
if [ "$ENVIRONMENT" = "prod" ]; then
    export CANARY_NAME="${CANARY_NAME:-prod-on-premises-monitor}"
    export MONITORING_FREQUENCY="${MONITORING_FREQUENCY:-rate(5 minutes)}"
    export ALARM_THRESHOLD="${ALARM_THRESHOLD:-2}"
    export ARTIFACT_RETENTION_DAYS="${ARTIFACT_RETENTION_DAYS:-30}"
else
    export CANARY_NAME="${CANARY_NAME:-dev-on-premises-monitor}"
    export MONITORING_FREQUENCY="${MONITORING_FREQUENCY:-rate(10 minutes)}"
    export ALARM_THRESHOLD="${ALARM_THRESHOLD:-3}"
    export ARTIFACT_RETENTION_DAYS="${ARTIFACT_RETENTION_DAYS:-7}"
fi

# Validate required environment variables
if [ -z "$VPC_ID" ]; then
    echo "Error: VPC_ID is required. Set via --vpc-id or VPC_ID environment variable."
    exit 1
fi

if [ -z "$SUBNET_IDS" ]; then
    echo "Error: SUBNET_IDS is required. Set via --subnet-ids or SUBNET_IDS environment variable."
    exit 1
fi

if [ -z "$NOTIFICATION_EMAIL" ]; then
    echo "Error: NOTIFICATION_EMAIL is required. Set via --notification-email or NOTIFICATION_EMAIL environment variable."
    exit 1
fi

# Bootstrap CDK if needed
echo "Checking CDK bootstrap status..."
cdk bootstrap

# Synthesize the stack
echo "Synthesizing CDK stack..."
cdk synth

# Deploy the stack
echo "Deploying CDK stack..."
cdk deploy --require-approval never

if [ $? -eq 0 ]; then
    echo "CDK deployment completed successfully!"
    
    # Display stack outputs
    echo ""
    echo "Stack Outputs:"
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue,Description]' \
        --output table
else
    echo "Error: CDK deployment failed."
    exit 1
fi