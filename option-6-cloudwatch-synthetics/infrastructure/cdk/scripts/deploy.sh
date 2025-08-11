#!/bin/bash

# CDK Deployment Script for CloudWatch Synthetics Monitoring
# This script provides automated deployment with parameter validation and environment setup

set -e

# Default values
ENVIRONMENT="dev"
REGION="us-east-1"
PROFILE=""
CONTEXT_FILE=""
SKIP_BOOTSTRAP=false
DESTROY=false
DIFF_ONLY=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy CloudWatch Synthetics Canary monitoring infrastructure using AWS CDK.

OPTIONS:
    -e, --environment ENV       Environment name (dev, staging, prod) [default: dev]
    -r, --region REGION         AWS region [default: us-east-1]
    -p, --profile PROFILE       AWS profile to use
    -c, --context FILE          Context file with deployment parameters
    -b, --skip-bootstrap        Skip CDK bootstrap (use if already bootstrapped)
    -d, --destroy               Destroy the stack instead of deploying
    --diff                      Show diff only, don't deploy
    -v, --verbose               Enable verbose output
    -h, --help                  Show this help message

EXAMPLES:
    # Deploy to dev environment
    $0 --environment dev --region us-east-1

    # Deploy with custom context file
    $0 --context ./config/prod-config.json --environment prod

    # Show deployment diff
    $0 --diff --environment staging

    # Destroy stack
    $0 --destroy --environment dev

REQUIRED ENVIRONMENT VARIABLES OR CONTEXT:
    - VPC_ID: VPC ID where canaries will run
    - SUBNET_IDS: Comma-separated list of subnet IDs
    - NOTIFICATION_EMAIL: Email for alarm notifications
    - TARGET_ENDPOINT: On-premises endpoint to monitor
    - ON_PREMISES_CIDR: CIDR block for on-premises network

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -c|--context)
            CONTEXT_FILE="$2"
            shift 2
            ;;
        -b|--skip-bootstrap)
            SKIP_BOOTSTRAP=true
            shift
            ;;
        -d|--destroy)
            DESTROY=true
            shift
            ;;
        --diff)
            DIFF_ONLY=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Set AWS profile if provided
if [[ -n "$PROFILE" ]]; then
    export AWS_PROFILE="$PROFILE"
    print_status "Using AWS profile: $PROFILE"
fi

# Set AWS region
export AWS_DEFAULT_REGION="$REGION"
export CDK_DEFAULT_REGION="$REGION"

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [[ -z "$ACCOUNT_ID" ]]; then
    print_error "Failed to get AWS account ID. Check your AWS credentials."
    exit 1
fi

export CDK_DEFAULT_ACCOUNT="$ACCOUNT_ID"
print_status "Deploying to account: $ACCOUNT_ID, region: $REGION"

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    print_error "Environment must be one of: dev, staging, prod"
    exit 1
fi

# Load context from file if provided
if [[ -n "$CONTEXT_FILE" ]]; then
    if [[ ! -f "$CONTEXT_FILE" ]]; then
        print_error "Context file not found: $CONTEXT_FILE"
        exit 1
    fi
    print_status "Loading context from: $CONTEXT_FILE"
    
    # Extract values from JSON context file
    VPC_ID=$(jq -r '.vpcId // empty' "$CONTEXT_FILE")
    SUBNET_IDS=$(jq -r '.subnetIds // empty | join(",")' "$CONTEXT_FILE")
    NOTIFICATION_EMAIL=$(jq -r '.notificationEmail // empty' "$CONTEXT_FILE")
    TARGET_ENDPOINT=$(jq -r '.targetEndpoint // empty' "$CONTEXT_FILE")
    ON_PREMISES_CIDR=$(jq -r '.onPremisesCIDR // empty' "$CONTEXT_FILE")
    MONITORING_FREQUENCY=$(jq -r '.monitoringFrequency // "rate(5 minutes)"' "$CONTEXT_FILE")
    CANARY_NAME=$(jq -r '.canaryName // "on-premises-monitor"' "$CONTEXT_FILE")
fi

# Validate required parameters
REQUIRED_VARS=("VPC_ID" "SUBNET_IDS" "NOTIFICATION_EMAIL" "TARGET_ENDPOINT")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var}" ]]; then
        MISSING_VARS+=("$var")
    fi
done

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
    print_error "Missing required parameters:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    print_error "Set these as environment variables or provide them in a context file."
    exit 1
fi

# Set default values for optional parameters
ON_PREMISES_CIDR=${ON_PREMISES_CIDR:-"10.0.0.0/8"}
MONITORING_FREQUENCY=${MONITORING_FREQUENCY:-"rate(5 minutes)"}
CANARY_NAME=${CANARY_NAME:-"on-premises-monitor"}
TARGET_PORT=${TARGET_PORT:-80}
ALARM_THRESHOLD=${ALARM_THRESHOLD:-2}
ESCALATION_THRESHOLD=${ESCALATION_THRESHOLD:-5}
HIGH_LATENCY_THRESHOLD=${HIGH_LATENCY_THRESHOLD:-5000}
ARTIFACT_RETENTION_DAYS=${ARTIFACT_RETENTION_DAYS:-30}

# Stack name
STACK_NAME="CanaryInfrastructureStack-${ENVIRONMENT}"

print_header "CloudWatch Synthetics Canary Deployment"
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "Account: $ACCOUNT_ID"
echo "Stack Name: $STACK_NAME"
echo "VPC ID: $VPC_ID"
echo "Subnets: $SUBNET_IDS"
echo "Target: $TARGET_ENDPOINT"
echo "Monitoring Frequency: $MONITORING_FREQUENCY"
echo ""

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    print_error "AWS CDK is not installed. Install it with: npm install -g aws-cdk"
    exit 1
fi

# Check if we're in the right directory
if [[ ! -f "cdk.json" ]]; then
    print_error "cdk.json not found. Run this script from the CDK project root directory."
    exit 1
fi

# Install dependencies
print_status "Installing dependencies..."
npm install

# Build the project
print_status "Building TypeScript project..."
npm run build

# Bootstrap CDK if needed
if [[ "$SKIP_BOOTSTRAP" == false ]]; then
    print_status "Bootstrapping CDK (if needed)..."
    cdk bootstrap aws://$ACCOUNT_ID/$REGION
fi

# Prepare CDK context
CDK_CONTEXT_ARGS=(
    "--context" "canaryName=$CANARY_NAME"
    "--context" "monitoringFrequency=$MONITORING_FREQUENCY"
    "--context" "vpcId=$VPC_ID"
    "--context" "subnetIds=$SUBNET_IDS"
    "--context" "onPremisesCIDR=$ON_PREMISES_CIDR"
    "--context" "targetEndpoint=$TARGET_ENDPOINT"
    "--context" "targetPort=$TARGET_PORT"
    "--context" "notificationEmail=$NOTIFICATION_EMAIL"
    "--context" "alarmThreshold=$ALARM_THRESHOLD"
    "--context" "escalationThreshold=$ESCALATION_THRESHOLD"
    "--context" "highLatencyThreshold=$HIGH_LATENCY_THRESHOLD"
    "--context" "artifactRetentionDays=$ARTIFACT_RETENTION_DAYS"
)

# Add optional context if provided
if [[ -n "$ESCALATION_EMAIL" ]]; then
    CDK_CONTEXT_ARGS+=("--context" "escalationEmail=$ESCALATION_EMAIL")
fi

if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
    CDK_CONTEXT_ARGS+=("--context" "slackWebhookUrl=$SLACK_WEBHOOK_URL")
fi

# Enable verbose output if requested
if [[ "$VERBOSE" == true ]]; then
    CDK_CONTEXT_ARGS+=("--verbose")
fi

# Execute CDK command based on operation
if [[ "$DESTROY" == true ]]; then
    print_warning "This will destroy the stack: $STACK_NAME"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Destroying stack..."
        cdk destroy "$STACK_NAME" "${CDK_CONTEXT_ARGS[@]}" --force
        print_status "Stack destroyed successfully!"
    else
        print_status "Destruction cancelled."
    fi
elif [[ "$DIFF_ONLY" == true ]]; then
    print_status "Showing deployment diff..."
    cdk diff "$STACK_NAME" "${CDK_CONTEXT_ARGS[@]}"
else
    print_status "Deploying stack..."
    cdk deploy "$STACK_NAME" "${CDK_CONTEXT_ARGS[@]}" --require-approval never
    
    print_status "Deployment completed successfully!"
    print_status "Stack outputs:"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
fi

print_header "Deployment Summary"
echo "Stack Name: $STACK_NAME"
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "Status: $(if [[ "$DESTROY" == true ]]; then echo "DESTROYED"; else echo "DEPLOYED"; fi)"
echo ""
print_status "Done!"