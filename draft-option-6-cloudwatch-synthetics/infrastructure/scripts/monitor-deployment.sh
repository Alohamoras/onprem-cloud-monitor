#!/bin/bash

# Deployment Status Monitoring Script for CloudWatch Synthetics Canary Monitoring
# This script monitors deployment status and provides real-time updates

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"

# Default values
STACK_NAME=""
REGION="us-east-1"
PROFILE=""
MONITOR_TYPE="deployment"  # deployment, health, or both
TIMEOUT=3600  # 1 hour timeout
INTERVAL=30   # 30 seconds between checks
VERBOSE=false
CONTINUOUS=false
ALERT_EMAIL=""
WEBHOOK_URL=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Status tracking
LAST_STATUS=""
STATUS_CHANGE_COUNT=0
START_TIME=$(date +%s)

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

log_status() {
    echo -e "${CYAN}[STATUS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_header() {
    echo -e "${PURPLE}[MONITOR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Monitor CloudWatch Synthetics Canary deployment and health status.

OPTIONS:
    -s, --stack-name NAME       Stack name to monitor (required)
    -r, --region REGION         AWS region [default: us-east-1]
    -p, --profile PROFILE       AWS profile to use
    -t, --type TYPE             Monitor type (deployment|health|both) [default: deployment]
    --timeout SECONDS           Monitoring timeout in seconds [default: 3600]
    --interval SECONDS          Check interval in seconds [default: 30]
    --continuous                Continue monitoring after deployment completes
    --alert-email EMAIL         Send email alerts on status changes
    --webhook-url URL           Send webhook notifications on status changes
    -v, --verbose               Enable verbose output
    -h, --help                  Show this help message

MONITOR TYPES:
    deployment      Monitor CloudFormation/CDK stack deployment status
    health          Monitor canary health and execution status
    both            Monitor both deployment and health status

EXAMPLES:
    # Monitor deployment status
    $0 --stack-name my-canary-stack --type deployment

    # Monitor health status continuously
    $0 --stack-name my-canary-stack --type health --continuous

    # Monitor with email alerts
    $0 --stack-name my-canary-stack --alert-email admin@example.com

    # Monitor with custom timeout and interval
    $0 --stack-name my-canary-stack --timeout 7200 --interval 60

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--stack-name)
            STACK_NAME="$2"
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
            MONITOR_TYPE="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --continuous)
            CONTINUOUS=true
            shift
            ;;
        --alert-email)
            ALERT_EMAIL="$2"
            shift 2
            ;;
        --webhook-url)
            WEBHOOK_URL="$2"
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
if [[ -z "$STACK_NAME" ]]; then
    log_error "Stack name is required. Use --stack-name option."
    show_usage
    exit 1
fi

# Validate monitor type
if [[ ! "$MONITOR_TYPE" =~ ^(deployment|health|both)$ ]]; then
    log_error "Invalid monitor type: $MONITOR_TYPE"
    show_usage
    exit 1
fi

# Initialize logging
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/monitor-$(date '+%Y%m%d-%H%M%S').log"
touch "$LOG_FILE"

log_header "Starting CloudWatch Synthetics Canary Monitoring"

# Set AWS profile if provided
if [[ -n "$PROFILE" ]]; then
    export AWS_PROFILE="$PROFILE"
    log_info "Using AWS profile: $PROFILE"
fi

# Set AWS region
export AWS_DEFAULT_REGION="$REGION"

log_info "Monitoring Configuration:"
log_info "  Stack Name: $STACK_NAME"
log_info "  Region: $REGION"
log_info "  Monitor Type: $MONITOR_TYPE"
log_info "  Timeout: ${TIMEOUT}s"
log_info "  Interval: ${INTERVAL}s"
log_info "  Continuous: $CONTINUOUS"
log_info "  Alert Email: ${ALERT_EMAIL:-'None'}"
log_info "  Webhook URL: ${WEBHOOK_URL:-'None'}"

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
    log_info "AWS Account ID: $ACCOUNT_ID"
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it for JSON processing."
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Function to send alert notification
send_alert() {
    local message="$1"
    local status="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_debug "Sending alert: $message"
    
    # Send email alert if configured
    if [[ -n "$ALERT_EMAIL" ]]; then
        local subject="CloudWatch Synthetics Alert - $STACK_NAME"
        local body="Stack: $STACK_NAME
Region: $REGION
Status: $status
Message: $message
Timestamp: $timestamp
Duration: $(($(date +%s) - START_TIME))s"
        
        # Use AWS SES if available, otherwise try local mail
        if aws ses send-email \
            --source "$ALERT_EMAIL" \
            --destination "ToAddresses=$ALERT_EMAIL" \
            --message "Subject={Data='$subject'},Body={Text={Data='$body'}}" \
            --region "$REGION" 2>/dev/null; then
            log_debug "Email alert sent successfully"
        else
            log_debug "Failed to send email alert via SES, trying local mail"
            echo "$body" | mail -s "$subject" "$ALERT_EMAIL" 2>/dev/null || log_debug "Failed to send email alert"
        fi
    fi
    
    # Send webhook notification if configured
    if [[ -n "$WEBHOOK_URL" ]]; then
        local webhook_payload=$(cat << EOF
{
    "stack": "$STACK_NAME",
    "region": "$REGION",
    "status": "$status",
    "message": "$message",
    "timestamp": "$timestamp",
    "duration": $(($(date +%s) - START_TIME))
}
EOF
)
        
        if curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$webhook_payload" \
            "$WEBHOOK_URL" >/dev/null; then
            log_debug "Webhook notification sent successfully"
        else
            log_debug "Failed to send webhook notification"
        fi
    fi
}

# Function to get stack status
get_stack_status() {
    local stack_info
    
    if ! stack_info=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null); then
        echo "NOT_FOUND"
        return 1
    fi
    
    echo "$stack_info" | jq -r '.Stacks[0].StackStatus'
}

# Function to get stack events
get_recent_stack_events() {
    local max_items=${1:-5}
    
    aws cloudformation describe-stack-events \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --max-items "$max_items" \
        --query 'StackEvents[*].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]' \
        --output table 2>/dev/null || echo "No events available"
}

# Function to get canary status
get_canary_status() {
    local canaries
    
    # Get canaries from stack resources
    canaries=$(aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'StackResources[?ResourceType==`AWS::Synthetics::Canary`].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$canaries" || "$canaries" == "None" ]]; then
        echo "NO_CANARIES"
        return 1
    fi
    
    local overall_status="HEALTHY"
    local canary_details=""
    
    for canary in $canaries; do
        if [[ -z "$canary" ]]; then
            continue
        fi
        
        local canary_info
        if canary_info=$(aws synthetics get-canary --name "$canary" --region "$REGION" 2>/dev/null); then
            local state=$(echo "$canary_info" | jq -r '.Canary.Status.State')
            local last_run=$(echo "$canary_info" | jq -r '.Canary.Status.LastRun.Status.State // "UNKNOWN"')
            
            canary_details="$canary_details\n  $canary: State=$state, LastRun=$last_run"
            
            if [[ "$state" != "RUNNING" || "$last_run" == "FAILED" ]]; then
                overall_status="UNHEALTHY"
            fi
        else
            canary_details="$canary_details\n  $canary: ERROR (cannot retrieve status)"
            overall_status="UNHEALTHY"
        fi
    done
    
    echo -e "$overall_status$canary_details"
}

# Function to monitor deployment status
monitor_deployment() {
    log_info "Starting deployment monitoring..."
    
    local current_status
    local elapsed_time
    local status_details
    
    while true; do
        elapsed_time=$(($(date +%s) - START_TIME))
        
        # Check timeout
        if [[ $elapsed_time -gt $TIMEOUT ]]; then
            log_error "Monitoring timeout reached (${TIMEOUT}s)"
            send_alert "Monitoring timeout reached" "TIMEOUT"
            return 1
        fi
        
        # Get current status
        current_status=$(get_stack_status)
        
        # Check for status change
        if [[ "$current_status" != "$LAST_STATUS" ]]; then
            if [[ -n "$LAST_STATUS" ]]; then
                log_status "Status changed: $LAST_STATUS -> $current_status"
                send_alert "Stack status changed from $LAST_STATUS to $current_status" "$current_status"
                ((STATUS_CHANGE_COUNT++))
            else
                log_status "Initial status: $current_status"
            fi
            
            LAST_STATUS="$current_status"
            
            # Show recent events on status change
            if [[ "$VERBOSE" == true ]]; then
                log_debug "Recent stack events:"
                get_recent_stack_events 3
            fi
        else
            log_debug "Status unchanged: $current_status (${elapsed_time}s elapsed)"
        fi
        
        # Check for terminal states
        case "$current_status" in
            "CREATE_COMPLETE"|"UPDATE_COMPLETE")
                log_info "Deployment completed successfully: $current_status"
                send_alert "Deployment completed successfully" "$current_status"
                
                if [[ "$CONTINUOUS" != true ]]; then
                    return 0
                else
                    log_info "Continuing monitoring in continuous mode..."
                    break  # Exit deployment monitoring, continue with health monitoring
                fi
                ;;
            "CREATE_FAILED"|"UPDATE_FAILED"|"ROLLBACK_COMPLETE"|"UPDATE_ROLLBACK_COMPLETE")
                log_error "Deployment failed: $current_status"
                send_alert "Deployment failed" "$current_status"
                
                # Show failure details
                log_error "Recent stack events:"
                get_recent_stack_events 10
                
                return 1
                ;;
            "DELETE_COMPLETE")
                log_info "Stack deleted successfully"
                send_alert "Stack deleted successfully" "$current_status"
                return 0
                ;;
            "DELETE_FAILED")
                log_error "Stack deletion failed"
                send_alert "Stack deletion failed" "$current_status"
                return 1
                ;;
            "NOT_FOUND")
                log_warn "Stack not found"
                if [[ "$CONTINUOUS" != true ]]; then
                    return 1
                fi
                ;;
        esac
        
        # Wait before next check
        sleep "$INTERVAL"
    done
}

# Function to monitor health status
monitor_health() {
    log_info "Starting health monitoring..."
    
    local current_health
    local elapsed_time
    
    while true; do
        elapsed_time=$(($(date +%s) - START_TIME))
        
        # Check timeout (only if not continuous)
        if [[ "$CONTINUOUS" != true && $elapsed_time -gt $TIMEOUT ]]; then
            log_error "Health monitoring timeout reached (${TIMEOUT}s)"
            send_alert "Health monitoring timeout reached" "TIMEOUT"
            return 1
        fi
        
        # Get current health status
        current_health=$(get_canary_status)
        local health_status=$(echo "$current_health" | head -n1)
        local health_details=$(echo "$current_health" | tail -n +2)
        
        # Check for health change
        if [[ "$health_status" != "$LAST_STATUS" ]]; then
            if [[ -n "$LAST_STATUS" ]]; then
                log_status "Health changed: $LAST_STATUS -> $health_status"
                send_alert "Canary health changed from $LAST_STATUS to $health_status" "$health_status"
                ((STATUS_CHANGE_COUNT++))
            else
                log_status "Initial health: $health_status"
            fi
            
            LAST_STATUS="$health_status"
            
            # Show health details
            if [[ -n "$health_details" ]]; then
                log_info "Canary details:$health_details"
            fi
        else
            log_debug "Health unchanged: $health_status (${elapsed_time}s elapsed)"
        fi
        
        # Handle health states
        case "$health_status" in
            "HEALTHY")
                log_debug "All canaries are healthy"
                ;;
            "UNHEALTHY")
                log_warn "One or more canaries are unhealthy"
                if [[ -n "$health_details" ]]; then
                    log_warn "Unhealthy canaries:$health_details"
                fi
                ;;
            "NO_CANARIES")
                log_warn "No canaries found in stack"
                if [[ "$CONTINUOUS" != true ]]; then
                    return 1
                fi
                ;;
        esac
        
        # Wait before next check
        sleep "$INTERVAL"
    done
}

# Function to display monitoring summary
display_monitoring_summary() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    
    log_info "Monitoring Summary:"
    log_info "  Stack Name: $STACK_NAME"
    log_info "  Monitor Type: $MONITOR_TYPE"
    log_info "  Final Status: ${LAST_STATUS:-'Unknown'}"
    log_info "  Status Changes: $STATUS_CHANGE_COUNT"
    log_info "  Total Duration: ${total_duration}s"
    log_info "  Log File: $LOG_FILE"
}

# Signal handler for graceful shutdown
cleanup() {
    log_info "Monitoring interrupted by user"
    display_monitoring_summary
    exit 0
}

trap cleanup SIGINT SIGTERM

# Main execution function
main() {
    local exit_code=0
    
    check_prerequisites
    
    case "$MONITOR_TYPE" in
        "deployment")
            monitor_deployment || exit_code=$?
            ;;
        "health")
            monitor_health || exit_code=$?
            ;;
        "both")
            # First monitor deployment, then health
            if monitor_deployment; then
                log_info "Deployment monitoring completed, switching to health monitoring..."
                LAST_STATUS=""  # Reset status for health monitoring
                monitor_health || exit_code=$?
            else
                exit_code=1
            fi
            ;;
    esac
    
    display_monitoring_summary
    log_header "Monitoring completed!"
    
    return $exit_code
}

# Execute main function
main "$@"