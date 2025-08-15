#!/bin/bash

# Comprehensive Deployment Automation Script for CloudWatch Synthetics Canary Monitoring
# This script provides automated deployment with parameter validation, pre-deployment checks,
# rollback capabilities, and deployment status monitoring

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
BACKUP_DIR="$PROJECT_ROOT/backups"

# Default values
DEPLOYMENT_TYPE="cloudformation"  # cloudformation or cdk
ENVIRONMENT="dev"
REGION="us-east-1"
STACK_NAME=""
PROFILE=""
CONFIG_FILE=""
DRY_RUN=false
SKIP_VALIDATION=false
SKIP_BACKUP=false
AUTO_ROLLBACK=true
VERBOSE=false
FORCE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    fi
}

log_header() {
    echo -e "${PURPLE}[DEPLOY]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Comprehensive deployment automation for CloudWatch Synthetics Canary monitoring.

OPTIONS:
    -t, --type TYPE             Deployment type (cloudformation|cdk) [default: cloudformation]
    -e, --environment ENV       Environment name (dev, staging, prod) [default: dev]
    -r, --region REGION         AWS region [default: us-east-1]
    -s, --stack-name NAME       Custom stack name (auto-generated if not provided)
    -p, --profile PROFILE       AWS profile to use
    -c, --config FILE           Configuration file with deployment parameters
    --dry-run                   Perform validation and show what would be deployed
    --skip-validation           Skip pre-deployment validation checks
    --skip-backup               Skip backup of existing resources
    --no-rollback               Disable automatic rollback on failure
    -f, --force                 Force deployment even if validation warnings exist
    -v, --verbose               Enable verbose output
    -h, --help                  Show this help message

EXAMPLES:
    # Deploy using CloudFormation with config file
    $0 --type cloudformation --environment prod --config ./config/prod.json

    # Deploy using CDK with dry run
    $0 --type cdk --environment dev --dry-run

    # Deploy with custom stack name and profile
    $0 --stack-name my-canary-stack --profile production --environment prod

CONFIGURATION FILE FORMAT (JSON):
    {
        "vpcId": "vpc-12345678",
        "subnetIds": ["subnet-12345678", "subnet-87654321"],
        "notificationEmail": "admin@example.com",
        "targetEndpoint": "192.168.1.100",
        "targetPort": 8080,
        "onPremisesCIDR": "192.168.0.0/16",
        "monitoringFrequency": "rate(5 minutes)",
        "canaryName": "production-monitor",
        "alarmThreshold": 2,
        "escalationThreshold": 5,
        "highLatencyThreshold": 5000,
        "artifactRetentionDays": 30
    }

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            DEPLOYMENT_TYPE="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --no-rollback)
            AUTO_ROLLBACK=false
            shift
            ;;
        -f|--force)
            FORCE=true
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
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Initialize logging
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deployment-$(date '+%Y%m%d-%H%M%S').log"
touch "$LOG_FILE"

# Initialize backup directory
mkdir -p "$BACKUP_DIR"

log_header "Starting CloudWatch Synthetics Canary Deployment Automation"

# Validate deployment type
if [[ ! "$DEPLOYMENT_TYPE" =~ ^(cloudformation|cdk)$ ]]; then
    log_error "Deployment type must be 'cloudformation' or 'cdk'"
    exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    log_error "Environment must be one of: dev, staging, prod"
    exit 1
fi

# Set AWS profile if provided
if [[ -n "$PROFILE" ]]; then
    export AWS_PROFILE="$PROFILE"
    log_info "Using AWS profile: $PROFILE"
fi

# Set AWS region
export AWS_DEFAULT_REGION="$REGION"
export CDK_DEFAULT_REGION="$REGION"

# Generate stack name if not provided
if [[ -z "$STACK_NAME" ]]; then
    if [[ "$DEPLOYMENT_TYPE" == "cdk" ]]; then
        STACK_NAME="CanaryInfrastructureStack-${ENVIRONMENT}"
    else
        STACK_NAME="cloudwatch-synthetics-monitoring-${ENVIRONMENT}"
    fi
fi

log_info "Deployment Configuration:"
log_info "  Type: $DEPLOYMENT_TYPE"
log_info "  Environment: $ENVIRONMENT"
log_info "  Region: $REGION"
log_info "  Stack Name: $STACK_NAME"
log_info "  Config File: ${CONFIG_FILE:-'None (using environment variables)'}"
log_info "  Dry Run: $DRY_RUN"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Get AWS account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export CDK_DEFAULT_ACCOUNT="$ACCOUNT_ID"
    log_info "AWS Account ID: $ACCOUNT_ID"
    
    # Check deployment type specific prerequisites
    if [[ "$DEPLOYMENT_TYPE" == "cdk" ]]; then
        if ! command -v cdk &> /dev/null; then
            log_error "AWS CDK is not installed. Install it with: npm install -g aws-cdk"
            exit 1
        fi
        
        if ! command -v node &> /dev/null; then
            log_error "Node.js is not installed. Please install it first."
            exit 1
        fi
        
        if ! command -v npm &> /dev/null; then
            log_error "npm is not installed. Please install it first."
            exit 1
        fi
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it for JSON processing."
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Function to load and validate configuration
load_configuration() {
    log_info "Loading configuration..."
    
    # Load from config file if provided
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            log_error "Configuration file not found: $CONFIG_FILE"
            exit 1
        fi
        
        log_info "Loading configuration from: $CONFIG_FILE"
        
        # Validate JSON format
        if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
            log_error "Invalid JSON format in configuration file: $CONFIG_FILE"
            exit 1
        fi
        
        # Extract configuration values
        VPC_ID=$(jq -r '.vpcId // empty' "$CONFIG_FILE")
        SUBNET_IDS=$(jq -r '.subnetIds // empty | if type == "array" then join(",") else . end' "$CONFIG_FILE")
        NOTIFICATION_EMAIL=$(jq -r '.notificationEmail // empty' "$CONFIG_FILE")
        TARGET_ENDPOINT=$(jq -r '.targetEndpoint // empty' "$CONFIG_FILE")
        TARGET_PORT=$(jq -r '.targetPort // 80' "$CONFIG_FILE")
        ON_PREMISES_CIDR=$(jq -r '.onPremisesCIDR // "10.0.0.0/8"' "$CONFIG_FILE")
        MONITORING_FREQUENCY=$(jq -r '.monitoringFrequency // "rate(5 minutes)"' "$CONFIG_FILE")
        CANARY_NAME=$(jq -r '.canaryName // "on-premises-monitor"' "$CONFIG_FILE")
        ALARM_THRESHOLD=$(jq -r '.alarmThreshold // 2' "$CONFIG_FILE")
        ESCALATION_THRESHOLD=$(jq -r '.escalationThreshold // 5' "$CONFIG_FILE")
        HIGH_LATENCY_THRESHOLD=$(jq -r '.highLatencyThreshold // 5000' "$CONFIG_FILE")
        ARTIFACT_RETENTION_DAYS=$(jq -r '.artifactRetentionDays // 30' "$CONFIG_FILE")
        ESCALATION_EMAIL=$(jq -r '.escalationEmail // empty' "$CONFIG_FILE")
        SLACK_WEBHOOK_URL=$(jq -r '.slackWebhookUrl // empty' "$CONFIG_FILE")
    fi
    
    # Set defaults for missing values
    VPC_ID=${VPC_ID:-$VPC_ID}
    SUBNET_IDS=${SUBNET_IDS:-$SUBNET_IDS}
    NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL:-$NOTIFICATION_EMAIL}
    TARGET_ENDPOINT=${TARGET_ENDPOINT:-$TARGET_ENDPOINT}
    TARGET_PORT=${TARGET_PORT:-80}
    ON_PREMISES_CIDR=${ON_PREMISES_CIDR:-"10.0.0.0/8"}
    MONITORING_FREQUENCY=${MONITORING_FREQUENCY:-"rate(5 minutes)"}
    CANARY_NAME=${CANARY_NAME:-"${ENVIRONMENT}-on-premises-monitor"}
    ALARM_THRESHOLD=${ALARM_THRESHOLD:-2}
    ESCALATION_THRESHOLD=${ESCALATION_THRESHOLD:-5}
    HIGH_LATENCY_THRESHOLD=${HIGH_LATENCY_THRESHOLD:-5000}
    ARTIFACT_RETENTION_DAYS=${ARTIFACT_RETENTION_DAYS:-30}
    
    # Validate required parameters
    REQUIRED_VARS=("VPC_ID" "SUBNET_IDS" "NOTIFICATION_EMAIL" "TARGET_ENDPOINT")
    MISSING_VARS=()
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var}" ]]; then
            MISSING_VARS+=("$var")
        fi
    done
    
    if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
        log_error "Missing required configuration parameters:"
        for var in "${MISSING_VARS[@]}"; do
            log_error "  - $var"
        done
        log_error "Set these as environment variables or provide them in a configuration file."
        exit 1
    fi
    
    log_info "Configuration loaded successfully"
    log_debug "VPC ID: $VPC_ID"
    log_debug "Subnet IDs: $SUBNET_IDS"
    log_debug "Target Endpoint: $TARGET_ENDPOINT:$TARGET_PORT"
    log_debug "Monitoring Frequency: $MONITORING_FREQUENCY"
}

# Function to perform pre-deployment validation
validate_deployment() {
    if [[ "$SKIP_VALIDATION" == true ]]; then
        log_warn "Skipping pre-deployment validation"
        return 0
    fi
    
    log_info "Performing pre-deployment validation..."
    
    local validation_errors=0
    local validation_warnings=0
    
    # Validate VPC exists and is accessible
    log_debug "Validating VPC: $VPC_ID"
    if ! aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$REGION" &>/dev/null; then
        log_error "VPC $VPC_ID not found or not accessible in region $REGION"
        ((validation_errors++))
    else
        log_debug "VPC validation passed"
    fi
    
    # Validate subnets exist and are in the VPC
    log_debug "Validating subnets: $SUBNET_IDS"
    IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
    for subnet in "${SUBNET_ARRAY[@]}"; do
        subnet=$(echo "$subnet" | xargs)  # trim whitespace
        if ! aws ec2 describe-subnets --subnet-ids "$subnet" --region "$REGION" &>/dev/null; then
            log_error "Subnet $subnet not found or not accessible"
            ((validation_errors++))
        else
            # Check if subnet is in the specified VPC
            subnet_vpc=$(aws ec2 describe-subnets --subnet-ids "$subnet" --region "$REGION" --query 'Subnets[0].VpcId' --output text)
            if [[ "$subnet_vpc" != "$VPC_ID" ]]; then
                log_error "Subnet $subnet is not in VPC $VPC_ID (found in $subnet_vpc)"
                ((validation_errors++))
            fi
        fi
    done
    
    # Validate email format
    if [[ ! "$NOTIFICATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email format: $NOTIFICATION_EMAIL"
        ((validation_errors++))
    fi
    
    # Validate target endpoint format
    if [[ ! "$TARGET_ENDPOINT" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && [[ ! "$TARGET_ENDPOINT" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_warn "Target endpoint format may be invalid: $TARGET_ENDPOINT"
        ((validation_warnings++))
    fi
    
    # Validate port range
    if [[ "$TARGET_PORT" -lt 1 || "$TARGET_PORT" -gt 65535 ]]; then
        log_error "Invalid port number: $TARGET_PORT (must be 1-65535)"
        ((validation_errors++))
    fi
    
    # Validate CIDR format
    if [[ ! "$ON_PREMISES_CIDR" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "Invalid CIDR format: $ON_PREMISES_CIDR"
        ((validation_errors++))
    fi
    
    # Validate monitoring frequency format
    if [[ ! "$MONITORING_FREQUENCY" =~ ^rate\([0-9]+ (minute|minutes|hour|hours|day|days)\)$ ]] && [[ ! "$MONITORING_FREQUENCY" =~ ^cron\(.+\)$ ]]; then
        log_error "Invalid monitoring frequency format: $MONITORING_FREQUENCY"
        ((validation_errors++))
    fi
    
    # Check if stack already exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        log_warn "Stack $STACK_NAME already exists and will be updated"
        ((validation_warnings++))
    fi
    
    # Validate template files exist
    if [[ "$DEPLOYMENT_TYPE" == "cloudformation" ]]; then
        TEMPLATE_FILE="$PROJECT_ROOT/cloudformation/main-template.yaml"
        if [[ ! -f "$TEMPLATE_FILE" ]]; then
            log_error "CloudFormation template not found: $TEMPLATE_FILE"
            ((validation_errors++))
        else
            # Validate template syntax
            if ! aws cloudformation validate-template --template-body "file://$TEMPLATE_FILE" --region "$REGION" &>/dev/null; then
                log_error "CloudFormation template validation failed"
                ((validation_errors++))
            fi
        fi
    elif [[ "$DEPLOYMENT_TYPE" == "cdk" ]]; then
        CDK_DIR="$PROJECT_ROOT/cdk"
        if [[ ! -f "$CDK_DIR/cdk.json" ]]; then
            log_error "CDK project not found: $CDK_DIR/cdk.json"
            ((validation_errors++))
        fi
    fi
    
    # Report validation results
    if [[ $validation_errors -gt 0 ]]; then
        log_error "Validation failed with $validation_errors error(s)"
        if [[ "$FORCE" != true ]]; then
            log_error "Use --force to proceed despite validation errors"
            exit 1
        else
            log_warn "Proceeding with deployment despite validation errors (--force specified)"
        fi
    elif [[ $validation_warnings -gt 0 ]]; then
        log_warn "Validation completed with $validation_warnings warning(s)"
    else
        log_info "Validation passed successfully"
    fi
}

# Function to backup existing resources
backup_existing_resources() {
    if [[ "$SKIP_BACKUP" == true ]]; then
        log_warn "Skipping backup of existing resources"
        return 0
    fi
    
    log_info "Backing up existing resources..."
    
    local backup_timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_file="$BACKUP_DIR/stack-backup-${STACK_NAME}-${backup_timestamp}.json"
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        log_info "Creating backup of existing stack: $STACK_NAME"
        
        # Export stack template
        aws cloudformation get-template --stack-name "$STACK_NAME" --region "$REGION" > "$backup_file"
        
        # Export stack parameters and outputs
        aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >> "$backup_file"
        
        log_info "Backup created: $backup_file"
        echo "$backup_file" > "$BACKUP_DIR/latest-backup.txt"
    else
        log_info "No existing stack to backup"
    fi
}

# Function to deploy using CloudFormation
deploy_cloudformation() {
    log_info "Deploying using CloudFormation..."
    
    local template_file="$PROJECT_ROOT/cloudformation/main-template.yaml"
    local parameters_file="$PROJECT_ROOT/cloudformation/parameters/${ENVIRONMENT}-parameters.json"
    
    # Create parameters file if it doesn't exist
    if [[ ! -f "$parameters_file" ]]; then
        log_info "Creating parameters file: $parameters_file"
        mkdir -p "$(dirname "$parameters_file")"
        
        cat > "$parameters_file" << EOF
[
    {
        "ParameterKey": "Environment",
        "ParameterValue": "$ENVIRONMENT"
    },
    {
        "ParameterKey": "VpcId",
        "ParameterValue": "$VPC_ID"
    },
    {
        "ParameterKey": "SubnetIds",
        "ParameterValue": "$SUBNET_IDS"
    },
    {
        "ParameterKey": "NotificationEmail",
        "ParameterValue": "$NOTIFICATION_EMAIL"
    },
    {
        "ParameterKey": "TargetEndpoint",
        "ParameterValue": "$TARGET_ENDPOINT"
    },
    {
        "ParameterKey": "TargetPort",
        "ParameterValue": "$TARGET_PORT"
    },
    {
        "ParameterKey": "OnPremisesCIDR",
        "ParameterValue": "$ON_PREMISES_CIDR"
    },
    {
        "ParameterKey": "MonitoringFrequency",
        "ParameterValue": "$MONITORING_FREQUENCY"
    },
    {
        "ParameterKey": "CanaryName",
        "ParameterValue": "$CANARY_NAME"
    },
    {
        "ParameterKey": "AlarmThreshold",
        "ParameterValue": "$ALARM_THRESHOLD"
    }
]
EOF
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would deploy CloudFormation stack with the following parameters:"
        cat "$parameters_file"
        return 0
    fi
    
    # Check if stack exists
    local operation="create-stack"
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        operation="update-stack"
    fi
    
    log_info "Executing CloudFormation $operation..."
    
    # Deploy the stack
    aws cloudformation "$operation" \
        --stack-name "$STACK_NAME" \
        --template-body "file://$template_file" \
        --parameters "file://$parameters_file" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION" \
        --tags Key=Environment,Value="$ENVIRONMENT" Key=DeployedBy,Value="automation-script"
    
    # Wait for operation to complete
    log_info "Waiting for stack operation to complete..."
    if [[ "$operation" == "create-stack" ]]; then
        aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION"
    else
        aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$REGION"
    fi
    
    log_info "CloudFormation deployment completed successfully"
}

# Function to deploy using CDK
deploy_cdk() {
    log_info "Deploying using CDK..."
    
    local cdk_dir="$PROJECT_ROOT/cdk"
    cd "$cdk_dir"
    
    # Install dependencies
    log_info "Installing CDK dependencies..."
    npm install
    
    # Build the project
    log_info "Building CDK project..."
    npm run build
    
    # Bootstrap CDK if needed
    log_info "Bootstrapping CDK (if needed)..."
    cdk bootstrap "aws://$ACCOUNT_ID/$REGION"
    
    # Prepare CDK context
    local cdk_context_args=(
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
    
    if [[ -n "$ESCALATION_EMAIL" ]]; then
        cdk_context_args+=("--context" "escalationEmail=$ESCALATION_EMAIL")
    fi
    
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        cdk_context_args+=("--context" "slackWebhookUrl=$SLACK_WEBHOOK_URL")
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Showing CDK diff..."
        cdk diff "$STACK_NAME" "${cdk_context_args[@]}"
        return 0
    fi
    
    log_info "Deploying CDK stack..."
    cdk deploy "$STACK_NAME" "${cdk_context_args[@]}" --require-approval never
    
    log_info "CDK deployment completed successfully"
}

# Function to monitor deployment status
monitor_deployment_status() {
    log_info "Monitoring deployment status..."
    
    local max_attempts=60
    local attempt=0
    local status=""
    
    while [[ $attempt -lt $max_attempts ]]; do
        status=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
        
        case "$status" in
            "CREATE_COMPLETE"|"UPDATE_COMPLETE")
                log_info "Deployment completed successfully with status: $status"
                return 0
                ;;
            "CREATE_FAILED"|"UPDATE_FAILED"|"ROLLBACK_COMPLETE"|"UPDATE_ROLLBACK_COMPLETE")
                log_error "Deployment failed with status: $status"
                return 1
                ;;
            "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS"|"UPDATE_ROLLBACK_IN_PROGRESS")
                log_debug "Deployment in progress: $status (attempt $((attempt + 1))/$max_attempts)"
                ;;
            "NOT_FOUND")
                log_error "Stack not found during monitoring"
                return 1
                ;;
            *)
                log_warn "Unknown deployment status: $status"
                ;;
        esac
        
        sleep 30
        ((attempt++))
    done
    
    log_error "Deployment monitoring timed out after $((max_attempts * 30)) seconds"
    return 1
}

# Function to handle rollback
handle_rollback() {
    if [[ "$AUTO_ROLLBACK" != true ]]; then
        log_warn "Auto-rollback is disabled"
        return 0
    fi
    
    log_warn "Initiating rollback due to deployment failure..."
    
    # Check if we have a backup
    local backup_file=""
    if [[ -f "$BACKUP_DIR/latest-backup.txt" ]]; then
        backup_file=$(cat "$BACKUP_DIR/latest-backup.txt")
    fi
    
    if [[ -n "$backup_file" && -f "$backup_file" ]]; then
        log_info "Rolling back to previous version using backup: $backup_file"
        
        # For now, we'll just delete the failed stack
        # In a more sophisticated implementation, we could restore from backup
        aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
        aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
        
        log_info "Failed stack deleted. Manual restoration from backup may be required."
    else
        log_warn "No backup found. Manual cleanup may be required."
    fi
}

# Function to display deployment results
display_results() {
    log_info "Deployment Results:"
    
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        log_info "Stack Outputs:"
        aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue,Description]' \
            --output table | tee -a "$LOG_FILE"
        
        log_info "Stack Resources:"
        aws cloudformation describe-stack-resources \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query 'StackResources[*].[LogicalResourceId,ResourceType,ResourceStatus]' \
            --output table | tee -a "$LOG_FILE"
    else
        log_error "Stack not found or deployment failed"
    fi
}

# Main execution function
main() {
    local exit_code=0
    
    # Trap errors for rollback
    trap 'exit_code=$?; if [[ $exit_code -ne 0 ]]; then handle_rollback; fi; exit $exit_code' ERR
    
    # Execute deployment steps
    check_prerequisites
    load_configuration
    validate_deployment
    backup_existing_resources
    
    if [[ "$DEPLOYMENT_TYPE" == "cloudformation" ]]; then
        deploy_cloudformation
    else
        deploy_cdk
    fi
    
    if [[ "$DRY_RUN" != true ]]; then
        monitor_deployment_status
        display_results
    fi
    
    log_header "Deployment automation completed successfully!"
    log_info "Log file: $LOG_FILE"
    
    return 0
}

# Execute main function
main "$@"