#!/bin/bash

# CloudFormation deployment script for CloudWatch Synthetics Canary Monitoring

set -e

# Default values
STACK_NAME="cloudwatch-synthetics-monitoring"
ENVIRONMENT="dev"
REGION="us-east-1"
TEMPLATE_FILE="cloudformation/main-template.yaml"

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
    --region)
      REGION="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  --stack-name NAME    CloudFormation stack name (default: cloudwatch-synthetics-monitoring)"
      echo "  --environment ENV    Environment (dev/prod) (default: dev)"
      echo "  --region REGION      AWS region (default: us-east-1)"
      echo "  --help              Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

PARAMETERS_FILE="cloudformation/parameters/${ENVIRONMENT}-parameters.json"

echo "Deploying CloudWatch Synthetics Canary Monitoring..."
echo "Stack Name: $STACK_NAME"
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "Template: $TEMPLATE_FILE"
echo "Parameters: $PARAMETERS_FILE"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file $TEMPLATE_FILE not found."
    exit 1
fi

# Check if parameters file exists
if [ ! -f "$PARAMETERS_FILE" ]; then
    echo "Error: Parameters file $PARAMETERS_FILE not found."
    echo "Please create the parameters file or use a different environment."
    exit 1
fi

# Validate the template
echo "Validating CloudFormation template..."
aws cloudformation validate-template \
    --template-body file://$TEMPLATE_FILE \
    --region $REGION

if [ $? -ne 0 ]; then
    echo "Error: Template validation failed."
    exit 1
fi

# Check if stack exists
STACK_EXISTS=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].StackName' \
    --output text 2>/dev/null || echo "NONE")

if [ "$STACK_EXISTS" = "NONE" ]; then
    echo "Creating new stack..."
    OPERATION="create-stack"
else
    echo "Updating existing stack..."
    OPERATION="update-stack"
fi

# Deploy the stack
echo "Deploying stack..."
aws cloudformation $OPERATION \
    --stack-name $STACK_NAME \
    --template-body file://$TEMPLATE_FILE \
    --parameters file://$PARAMETERS_FILE \
    --capabilities CAPABILITY_NAMED_IAM \
    --region $REGION

if [ $? -ne 0 ]; then
    echo "Error: Stack deployment failed."
    exit 1
fi

# Wait for stack operation to complete
echo "Waiting for stack operation to complete..."
if [ "$OPERATION" = "create-stack" ]; then
    aws cloudformation wait stack-create-complete \
        --stack-name $STACK_NAME \
        --region $REGION
else
    aws cloudformation wait stack-update-complete \
        --stack-name $STACK_NAME \
        --region $REGION
fi

if [ $? -eq 0 ]; then
    echo "Stack deployment completed successfully!"
    
    # Display stack outputs
    echo ""
    echo "Stack Outputs:"
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue,Description]' \
        --output table
else
    echo "Error: Stack deployment failed or timed out."
    exit 1
fi