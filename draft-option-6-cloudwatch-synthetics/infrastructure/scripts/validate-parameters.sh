#!/bin/bash

# Parameter Validation Script for CloudWatch Synthetics Canary Monitoring
# This script validates deployment parameters and configuration

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"

# Default values
CONFIG_FILE=""
REGION="us-east-1"
PROFILE=""
VALIDATION_TYPE="all"  # all, network, aws-resources, configuration
STRICT_MODE=false
VERBOSE=false
OUTPUT_FORMAT="text"  # text, json

# Validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0
VALIDATION_RESULTS=()

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
    ((VALIDATION_WARNINGS++))
    VALIDATION_RESULTS+=("WARNING: $1")
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    ((VALIDATION_ERRORS++))
    VALIDATION_RESULTS+=("ERROR: $1")
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    fi
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    VALIDATION_RESULTS+=("PASS: $1")
}

log_header() {
    echo -e "${PURPLE}[VALIDATE]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate parameters and configuration for CloudWatch Synthetics Canary deployment.

OPTIONS:
    -c, --config FILE           Configuration file to validate (required)
    -r, --region REGION         AWS region [default: us-east-1]
    -p, --profile PROFILE       AWS profile to use
    -t, --type TYPE             Validation type (all|network|aws-resources|configuration) [default: all]
    -s, --strict                Enable strict validation mode (warnings become errors)
    -o, --output FORMAT         Output format (text|json) [default: text]
    -v, --verbose               Enable verbose output
    -h, --help                  Show this help message

VALIDATION TYPES:
    all                Validate everything (network, AWS resources, configuration)
    network            Validate network connectivity and configuration
    aws-resources      Validate AWS resources (VPC, subnets, etc.)
    configuration      Validate configuration parameters only

EXAMPLES:
    # Validate all parameters
    $0 --config ./config/prod.json

    # Validate only network configuration
    $0 --config ./config/dev.json --type network

    # Strict validation with JSON output
    $0 --config ./config/prod.json --strict --output json

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
        -c|--config)
            CONFIG_FILE="$2"
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
        -t|--type)
            VALIDATION_TYPE="$2"
            shift 2
            ;;
        -s|--strict)
            STRICT_MODE=true
            shift
            ;;
        -o|--output)
            OUTPUT_FORMAT="$2"
            shift 2
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

# Validate required parameters
if [[ -z "$CONFIG_FILE" ]]; then
    log_error "Configuration file is required. Use --config option."
    show_usage
    exit 1
fi

# Validate validation type
if [[ ! "$VALIDATION_TYPE" =~ ^(all|network|aws-resources|configuration)$ ]]; then
    log_error "Invalid validation type: $VALIDATION_TYPE"
    show_usage
    exit 1
fi

# Validate output format
if [[ ! "$OUTPUT_FORMAT" =~ ^(text|json)$ ]]; then
    log_error "Invalid output format: $OUTPUT_FORMAT"
    show_usage
    exit 1
fi

# Initialize logging
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/validation-$(date '+%Y%m%d-%H%M%S').log"
touch "$LOG_FILE"

log_header "Starting Parameter Validation"

# Set AWS profile if provided
if [[ -n "$PROFILE" ]]; then
    export AWS_PROFILE="$PROFILE"
    log_info "Using AWS profile: $PROFILE"
fi

# Set AWS region
export AWS_DEFAULT_REGION="$REGION"

log_info "Validation Configuration:"
log_info "  Config File: $CONFIG_FILE"
log_info "  Region: $REGION"
log_info "  Validation Type: $VALIDATION_TYPE"
log_info "  Strict Mode: $STRICT_MODE"
log_info "  Output Format: $OUTPUT_FORMAT"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it for JSON processing."
        exit 1
    fi
    
    # Validate JSON format
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        log_error "Invalid JSON format in configuration file: $CONFIG_FILE"
        exit 1
    fi
    
    # Check AWS CLI for AWS resource validation
    if [[ "$VALIDATION_TYPE" =~ ^(all|aws-resources|network)$ ]]; then
        if ! command -v aws &> /dev/null; then
            log_error "AWS CLI is not installed. Please install it for AWS resource validation."
            exit 1
        fi
        
        # Check AWS credentials
        if ! aws sts get-caller-identity &> /dev/null; then
            log_error "AWS credentials not configured or invalid."
            exit 1
        fi
        
        # Get AWS account ID
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        log_info "AWS Account ID: $ACCOUNT_ID"
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load configuration
load_configuration() {
    log_info "Loading configuration from: $CONFIG_FILE"
    
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
    
    log_debug "Configuration loaded successfully"
    log_debug "VPC ID: $VPC_ID"
    log_debug "Subnet IDs: $SUBNET_IDS"
    log_debug "Target Endpoint: $TARGET_ENDPOINT:$TARGET_PORT"
    log_debug "Monitoring Frequency: $MONITORING_FREQUENCY"
}

# Function to validate configuration parameters
validate_configuration() {
    log_info "Validating configuration parameters..."
    
    # Validate required parameters
    local required_params=("vpcId" "subnetIds" "notificationEmail" "targetEndpoint")
    
    for param in "${required_params[@]}"; do
        local value=$(jq -r ".$param // empty" "$CONFIG_FILE")
        if [[ -z "$value" || "$value" == "null" ]]; then
            log_error "Required parameter missing: $param"
        else
            log_success "Required parameter present: $param"
        fi
    done
    
    # Validate email format
    if [[ -n "$NOTIFICATION_EMAIL" ]]; then
        if [[ "$NOTIFICATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            log_success "Notification email format is valid: $NOTIFICATION_EMAIL"
        else
            log_error "Invalid notification email format: $NOTIFICATION_EMAIL"
        fi
    fi
    
    # Validate escalation email if provided
    if [[ -n "$ESCALATION_EMAIL" ]]; then
        if [[ "$ESCALATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            log_success "Escalation email format is valid: $ESCALATION_EMAIL"
        else
            log_error "Invalid escalation email format: $ESCALATION_EMAIL"
        fi
    fi
    
    # Validate target endpoint format
    if [[ -n "$TARGET_ENDPOINT" ]]; then
        if [[ "$TARGET_ENDPOINT" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            # Validate IP address ranges
            IFS='.' read -ra IP_PARTS <<< "$TARGET_ENDPOINT"
            local valid_ip=true
            for part in "${IP_PARTS[@]}"; do
                if [[ $part -lt 0 || $part -gt 255 ]]; then
                    valid_ip=false
                    break
                fi
            done
            
            if [[ "$valid_ip" == true ]]; then
                log_success "Target endpoint IP format is valid: $TARGET_ENDPOINT"
            else
                log_error "Invalid IP address: $TARGET_ENDPOINT"
            fi
        elif [[ "$TARGET_ENDPOINT" =~ ^[a-zA-Z0-9.-]+$ ]]; then
            log_success "Target endpoint hostname format is valid: $TARGET_ENDPOINT"
        else
            log_warn "Target endpoint format may be invalid: $TARGET_ENDPOINT"
        fi
    fi
    
    # Validate port range
    if [[ -n "$TARGET_PORT" ]]; then
        if [[ "$TARGET_PORT" =~ ^[0-9]+$ && "$TARGET_PORT" -ge 1 && "$TARGET_PORT" -le 65535 ]]; then
            log_success "Target port is valid: $TARGET_PORT"
        else
            log_error "Invalid port number: $TARGET_PORT (must be 1-65535)"
        fi
    fi
    
    # Validate CIDR format
    if [[ -n "$ON_PREMISES_CIDR" ]]; then
        if [[ "$ON_PREMISES_CIDR" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            # Validate CIDR components
            local ip_part=$(echo "$ON_PREMISES_CIDR" | cut -d'/' -f1)
            local cidr_part=$(echo "$ON_PREMISES_CIDR" | cut -d'/' -f2)
            
            IFS='.' read -ra IP_PARTS <<< "$ip_part"
            local valid_cidr=true
            
            for part in "${IP_PARTS[@]}"; do
                if [[ $part -lt 0 || $part -gt 255 ]]; then
                    valid_cidr=false
                    break
                fi
            done
            
            if [[ $cidr_part -lt 0 || $cidr_part -gt 32 ]]; then
                valid_cidr=false
            fi
            
            if [[ "$valid_cidr" == true ]]; then
                log_success "On-premises CIDR format is valid: $ON_PREMISES_CIDR"
            else
                log_error "Invalid CIDR format: $ON_PREMISES_CIDR"
            fi
        else
            log_error "Invalid CIDR format: $ON_PREMISES_CIDR"
        fi
    fi
    
    # Validate monitoring frequency format
    if [[ -n "$MONITORING_FREQUENCY" ]]; then
        if [[ "$MONITORING_FREQUENCY" =~ ^rate\([0-9]+ (minute|minutes|hour|hours|day|days)\)$ ]]; then
            log_success "Monitoring frequency format is valid: $MONITORING_FREQUENCY"
        elif [[ "$MONITORING_FREQUENCY" =~ ^cron\(.+\)$ ]]; then
            log_success "Monitoring frequency cron format is valid: $MONITORING_FREQUENCY"
        else
            log_error "Invalid monitoring frequency format: $MONITORING_FREQUENCY"
        fi
    fi
    
    # Validate numeric thresholds
    local numeric_params=("alarmThreshold" "escalationThreshold" "highLatencyThreshold" "artifactRetentionDays")
    
    for param in "${numeric_params[@]}"; do
        local value=$(jq -r ".$param // empty" "$CONFIG_FILE")
        if [[ -n "$value" && "$value" != "null" ]]; then
            if [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 ]]; then
                log_success "Numeric parameter is valid: $param=$value"
            else
                log_error "Invalid numeric parameter: $param=$value (must be positive integer)"
            fi
        fi
    done
    
    # Validate canary name format
    if [[ -n "$CANARY_NAME" ]]; then
        if [[ "$CANARY_NAME" =~ ^[a-zA-Z0-9_-]+$ && ${#CANARY_NAME} -le 21 ]]; then
            log_success "Canary name format is valid: $CANARY_NAME"
        else
            log_error "Invalid canary name: $CANARY_NAME (must be alphanumeric, underscore, hyphen only, max 21 chars)"
        fi
    fi
    
    # Validate Slack webhook URL if provided
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        if [[ "$SLACK_WEBHOOK_URL" =~ ^https://hooks\.slack\.com/services/.+ ]]; then
            log_success "Slack webhook URL format is valid"
        else
            log_warn "Slack webhook URL format may be invalid: $SLACK_WEBHOOK_URL"
        fi
    fi
}

# Function to validate AWS resources
validate_aws_resources() {
    log_info "Validating AWS resources..."
    
    # Validate VPC exists and is accessible
    if [[ -n "$VPC_ID" ]]; then
        log_debug "Validating VPC: $VPC_ID"
        if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$REGION" &>/dev/null; then
            local vpc_state=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$REGION" --query 'Vpcs[0].State' --output text)
            if [[ "$vpc_state" == "available" ]]; then
                log_success "VPC is valid and available: $VPC_ID"
            else
                log_error "VPC is not available: $VPC_ID (state: $vpc_state)"
            fi
        else
            log_error "VPC not found or not accessible: $VPC_ID"
        fi
    fi
    
    # Validate subnets exist and are in the VPC
    if [[ -n "$SUBNET_IDS" ]]; then
        log_debug "Validating subnets: $SUBNET_IDS"
        IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
        
        for subnet in "${SUBNET_ARRAY[@]}"; do
            subnet=$(echo "$subnet" | xargs)  # trim whitespace
            if [[ -z "$subnet" ]]; then
                continue
            fi
            
            if aws ec2 describe-subnets --subnet-ids "$subnet" --region "$REGION" &>/dev/null; then
                local subnet_vpc=$(aws ec2 describe-subnets --subnet-ids "$subnet" --region "$REGION" --query 'Subnets[0].VpcId' --output text)
                local subnet_state=$(aws ec2 describe-subnets --subnet-ids "$subnet" --region "$REGION" --query 'Subnets[0].State' --output text)
                local subnet_az=$(aws ec2 describe-subnets --subnet-ids "$subnet" --region "$REGION" --query 'Subnets[0].AvailabilityZone' --output text)
                
                if [[ "$subnet_vpc" == "$VPC_ID" ]]; then
                    if [[ "$subnet_state" == "available" ]]; then
                        log_success "Subnet is valid and available: $subnet (AZ: $subnet_az)"
                    else
                        log_error "Subnet is not available: $subnet (state: $subnet_state)"
                    fi
                else
                    log_error "Subnet $subnet is not in VPC $VPC_ID (found in $subnet_vpc)"
                fi
            else
                log_error "Subnet not found or not accessible: $subnet"
            fi
        done
    fi
    
    # Check if we have permissions to create required resources
    log_debug "Checking IAM permissions..."
    
    # Test CloudFormation permissions
    if aws cloudformation list-stacks --region "$REGION" --max-items 1 &>/dev/null; then
        log_success "CloudFormation permissions are available"
    else
        log_warn "CloudFormation permissions may be insufficient"
    fi
    
    # Test Synthetics permissions
    if aws synthetics describe-canaries --region "$REGION" --max-results 1 &>/dev/null; then
        log_success "Synthetics permissions are available"
    else
        log_warn "Synthetics permissions may be insufficient"
    fi
    
    # Test S3 permissions
    if aws s3 ls &>/dev/null; then
        log_success "S3 permissions are available"
    else
        log_warn "S3 permissions may be insufficient"
    fi
    
    # Test CloudWatch permissions
    if aws cloudwatch list-metrics --region "$REGION" --max-records 1 &>/dev/null; then
        log_success "CloudWatch permissions are available"
    else
        log_warn "CloudWatch permissions may be insufficient"
    fi
    
    # Test SNS permissions
    if aws sns list-topics --region "$REGION" &>/dev/null; then
        log_success "SNS permissions are available"
    else
        log_warn "SNS permissions may be insufficient"
    fi
}

# Function to validate network connectivity
validate_network() {
    log_info "Validating network configuration..."
    
    # Check if target endpoint is reachable (basic connectivity test)
    if [[ -n "$TARGET_ENDPOINT" && -n "$TARGET_PORT" ]]; then
        log_debug "Testing connectivity to $TARGET_ENDPOINT:$TARGET_PORT"
        
        # Use timeout to avoid hanging
        if timeout 10 bash -c "</dev/tcp/$TARGET_ENDPOINT/$TARGET_PORT" 2>/dev/null; then
            log_success "Target endpoint is reachable: $TARGET_ENDPOINT:$TARGET_PORT"
        else
            log_warn "Target endpoint may not be reachable: $TARGET_ENDPOINT:$TARGET_PORT (this may be expected if VPN is required)"
        fi
    fi
    
    # Validate subnet routing and availability zones
    if [[ -n "$SUBNET_IDS" ]]; then
        log_debug "Validating subnet network configuration"
        IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
        
        local availability_zones=()
        for subnet in "${SUBNET_ARRAY[@]}"; do
            subnet=$(echo "$subnet" | xargs)
            if [[ -z "$subnet" ]]; then
                continue
            fi
            
            if aws ec2 describe-subnets --subnet-ids "$subnet" --region "$REGION" &>/dev/null; then
                local subnet_az=$(aws ec2 describe-subnets --subnet-ids "$subnet" --region "$REGION" --query 'Subnets[0].AvailabilityZone' --output text)
                availability_zones+=("$subnet_az")
            fi
        done
        
        # Check for multiple AZs (recommended for high availability)
        local unique_azs=($(printf "%s\n" "${availability_zones[@]}" | sort -u))
        if [[ ${#unique_azs[@]} -gt 1 ]]; then
            log_success "Subnets span multiple availability zones: ${unique_azs[*]}"
        else
            log_warn "All subnets are in the same availability zone: ${unique_azs[0]} (consider using multiple AZs for high availability)"
        fi
    fi
    
    # Validate CIDR overlap
    if [[ -n "$ON_PREMISES_CIDR" && -n "$VPC_ID" ]]; then
        log_debug "Checking for CIDR overlap with VPC"
        local vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$REGION" --query 'Vpcs[0].CidrBlock' --output text 2>/dev/null || echo "")
        
        if [[ -n "$vpc_cidr" ]]; then
            # Simple CIDR overlap check (basic implementation)
            local vpc_network=$(echo "$vpc_cidr" | cut -d'/' -f1)
            local onprem_network=$(echo "$ON_PREMISES_CIDR" | cut -d'/' -f1)
            
            if [[ "$vpc_network" != "$onprem_network" ]]; then
                log_success "No obvious CIDR overlap detected between VPC ($vpc_cidr) and on-premises ($ON_PREMISES_CIDR)"
            else
                log_warn "Potential CIDR overlap between VPC ($vpc_cidr) and on-premises ($ON_PREMISES_CIDR)"
            fi
        fi
    fi
}

# Function to output results
output_results() {
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        # JSON output
        local json_results=$(printf '%s\n' "${VALIDATION_RESULTS[@]}" | jq -R . | jq -s .)
        
        cat << EOF
{
    "validation_summary": {
        "total_checks": $((VALIDATION_ERRORS + VALIDATION_WARNINGS + $(echo "${VALIDATION_RESULTS[@]}" | grep -c "PASS:" || echo 0))),
        "errors": $VALIDATION_ERRORS,
        "warnings": $VALIDATION_WARNINGS,
        "passed": $(echo "${VALIDATION_RESULTS[@]}" | grep -c "PASS:" || echo 0),
        "strict_mode": $STRICT_MODE,
        "validation_type": "$VALIDATION_TYPE"
    },
    "results": $json_results,
    "configuration": {
        "config_file": "$CONFIG_FILE",
        "region": "$REGION",
        "vpc_id": "$VPC_ID",
        "target_endpoint": "$TARGET_ENDPOINT",
        "canary_name": "$CANARY_NAME"
    }
}
EOF
    else
        # Text output
        log_header "Validation Summary"
        log_info "Total Checks: $((VALIDATION_ERRORS + VALIDATION_WARNINGS + $(echo "${VALIDATION_RESULTS[@]}" | grep -c "PASS:" || echo 0)))"
        log_info "Errors: $VALIDATION_ERRORS"
        log_info "Warnings: $VALIDATION_WARNINGS"
        log_info "Passed: $(echo "${VALIDATION_RESULTS[@]}" | grep -c "PASS:" || echo 0)"
        
        if [[ $VALIDATION_ERRORS -gt 0 ]]; then
            log_error "Validation failed with $VALIDATION_ERRORS error(s)"
        elif [[ $VALIDATION_WARNINGS -gt 0 && "$STRICT_MODE" == true ]]; then
            log_error "Validation failed in strict mode with $VALIDATION_WARNINGS warning(s)"
        else
            log_success "Validation completed successfully"
        fi
    fi
}

# Main execution function
main() {
    local exit_code=0
    
    check_prerequisites
    load_configuration
    
    case "$VALIDATION_TYPE" in
        "all")
            validate_configuration
            validate_aws_resources
            validate_network
            ;;
        "configuration")
            validate_configuration
            ;;
        "aws-resources")
            validate_aws_resources
            ;;
        "network")
            validate_network
            ;;
    esac
    
    output_results
    
    # Determine exit code
    if [[ $VALIDATION_ERRORS -gt 0 ]]; then
        exit_code=1
    elif [[ $VALIDATION_WARNINGS -gt 0 && "$STRICT_MODE" == true ]]; then
        exit_code=1
    fi
    
    log_info "Log file: $LOG_FILE"
    return $exit_code
}

# Execute main function
main "$@"