#!/bin/bash

# Cleanup Script for CloudWatch Synthetics Canary Monitoring
# This script provides comprehensive cleanup of deployment resources

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
BACKUP_DIR="$PROJECT_ROOT/backups"

# Default values
STACK_NAME=""
REGION="us-east-1"
PROFILE=""
CLEANUP_TYPE="all"  # all, stack-only, artifacts-only, logs-only
RETENTION_DAYS=30
FORCE=false
VERBOSE=false
DRY_RUN=false

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
    echo -e "${PURPLE}[CLEANUP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup CloudWatch Synthetics Canary monitoring resources and artifacts.

OPTIONS:
    -s, --stack-name NAME       Stack name to cleanup (required for stack cleanup)
    -r, --region REGION         AWS region [default: us-east-1]
    -p, --profile PROFILE       AWS profile to use
    -t, --type TYPE             Cleanup type (all|stack-only|artifacts-only|logs-only) [default: all]
    --retention-days DAYS       Keep artifacts/logs newer than N days [default: 30]
    --dry-run                   Show what would be cleaned up without doing it
    -f, --force                 Force cleanup without confirmation
    -v, --verbose               Enable verbose output
    -h, --help                  Show this help message

CLEANUP TYPES:
    all                Clean up everything (stack, artifacts, logs, backups)
    stack-only         Clean up only the CloudFormation/CDK stack
    artifacts-only     Clean up only S3 artifacts and CloudWatch logs
    logs-only          Clean up only local log files and backups

EXAMPLES:
    # Clean up everything for a specific stack
    $0 --stack-name my-canary-stack --type all

    # Clean up only artifacts older than 7 days
    $0 --type artifacts-only --retention-days 7

    # Dry run to see what would be cleaned up
    $0 --stack-name my-canary-stack --dry-run

    # Clean up local logs and backups only
    $0 --type logs-only --retention-days 14

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
            CLEANUP_TYPE="$2"
            shift 2
            ;;
        --retention-days)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
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

# Validate cleanup type
if [[ ! "$CLEANUP_TYPE" =~ ^(all|stack-only|artifacts-only|logs-only)$ ]]; then
    log_error "Invalid cleanup type: $CLEANUP_TYPE"
    show_usage
    exit 1
fi

# Validate stack name for stack-related cleanup
if [[ "$CLEANUP_TYPE" =~ ^(all|stack-only)$ && -z "$STACK_NAME" ]]; then
    log_error "Stack name is required for cleanup type: $CLEANUP_TYPE"
    show_usage
    exit 1
fi

# Initialize logging
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-$(date '+%Y%m%d-%H%M%S').log"
touch "$LOG_FILE"

log_header "Starting CloudWatch Synthetics Canary Cleanup"

# Set AWS profile if provided
if [[ -n "$PROFILE" ]]; then
    export AWS_PROFILE="$PROFILE"
    log_info "Using AWS profile: $PROFILE"
fi

# Set AWS region
export AWS_DEFAULT_REGION="$REGION"

log_info "Cleanup Configuration:"
log_info "  Stack Name: ${STACK_NAME:-'N/A'}"
log_info "  Region: $REGION"
log_info "  Cleanup Type: $CLEANUP_TYPE"
log_info "  Retention Days: $RETENTION_DAYS"
log_info "  Dry Run: $DRY_RUN"
log_info "  Force: $FORCE"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI for stack-related cleanup
    if [[ "$CLEANUP_TYPE" =~ ^(all|stack-only|artifacts-only)$ ]]; then
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
    fi
    
    log_info "Prerequisites check passed"
}

# Function to get stack resources
get_stack_resources() {
    if [[ -z "$STACK_NAME" ]]; then
        return 0
    fi
    
    log_info "Getting stack resources for: $STACK_NAME"
    
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        log_warn "Stack $STACK_NAME not found in region $REGION"
        return 1
    fi
    
    # Get S3 bucket names
    S3_BUCKETS=$(aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'StackResources[?ResourceType==`AWS::S3::Bucket`].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    # Get CloudWatch Log Groups
    LOG_GROUPS=$(aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'StackResources[?ResourceType==`AWS::Logs::LogGroup`].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    # Get Synthetics Canaries
    CANARIES=$(aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'StackResources[?ResourceType==`AWS::Synthetics::Canary`].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    log_debug "Found S3 buckets: $S3_BUCKETS"
    log_debug "Found log groups: $LOG_GROUPS"
    log_debug "Found canaries: $CANARIES"
    
    return 0
}

# Function to cleanup S3 artifacts
cleanup_s3_artifacts() {
    if [[ -z "$S3_BUCKETS" ]]; then
        log_info "No S3 buckets found to cleanup"
        return 0
    fi
    
    log_info "Cleaning up S3 artifacts..."
    
    for bucket in $S3_BUCKETS; do
        if [[ -z "$bucket" ]]; then
            continue
        fi
        
        log_info "Processing S3 bucket: $bucket"
        
        # Check if bucket exists
        if ! aws s3api head-bucket --bucket "$bucket" --region "$REGION" 2>/dev/null; then
            log_warn "S3 bucket $bucket not found or not accessible"
            continue
        fi
        
        # List objects older than retention period
        local cutoff_date=$(date -d "$RETENTION_DAYS days ago" '+%Y-%m-%d')
        log_debug "Cleaning objects older than: $cutoff_date"
        
        # Get objects to delete
        local objects_to_delete=$(aws s3api list-objects-v2 \
            --bucket "$bucket" \
            --region "$REGION" \
            --query "Contents[?LastModified<='$cutoff_date'].Key" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$objects_to_delete" && "$objects_to_delete" != "None" ]]; then
            local object_count=$(echo "$objects_to_delete" | wc -w)
            log_info "Found $object_count objects to delete in bucket $bucket"
            
            if [[ "$DRY_RUN" == true ]]; then
                log_info "DRY RUN: Would delete the following objects:"
                echo "$objects_to_delete" | tr ' ' '\n' | head -10
                if [[ $object_count -gt 10 ]]; then
                    log_info "... and $((object_count - 10)) more objects"
                fi
            else
                # Delete objects in batches
                echo "$objects_to_delete" | tr ' ' '\n' | while read -r object_key; do
                    if [[ -n "$object_key" ]]; then
                        aws s3 rm "s3://$bucket/$object_key" --region "$REGION"
                        log_debug "Deleted: s3://$bucket/$object_key"
                    fi
                done
                log_info "Deleted $object_count objects from bucket $bucket"
            fi
        else
            log_info "No objects older than $RETENTION_DAYS days found in bucket $bucket"
        fi
    done
}

# Function to cleanup CloudWatch logs
cleanup_cloudwatch_logs() {
    if [[ -z "$LOG_GROUPS" ]]; then
        log_info "No CloudWatch log groups found to cleanup"
        return 0
    fi
    
    log_info "Cleaning up CloudWatch logs..."
    
    for log_group in $LOG_GROUPS; do
        if [[ -z "$log_group" ]]; then
            continue
        fi
        
        log_info "Processing log group: $log_group"
        
        # Check if log group exists
        if ! aws logs describe-log-groups --log-group-name-prefix "$log_group" --region "$REGION" --query 'logGroups[0]' --output text &>/dev/null; then
            log_warn "Log group $log_group not found"
            continue
        fi
        
        # Calculate retention timestamp
        local retention_timestamp=$(($(date +%s) - (RETENTION_DAYS * 24 * 60 * 60)))
        retention_timestamp=$((retention_timestamp * 1000))  # Convert to milliseconds
        
        # Get log streams older than retention period
        local old_streams=$(aws logs describe-log-streams \
            --log-group-name "$log_group" \
            --region "$REGION" \
            --query "logStreams[?lastEventTime<$retention_timestamp].logStreamName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$old_streams" && "$old_streams" != "None" ]]; then
            local stream_count=$(echo "$old_streams" | wc -w)
            log_info "Found $stream_count old log streams in $log_group"
            
            if [[ "$DRY_RUN" == true ]]; then
                log_info "DRY RUN: Would delete the following log streams:"
                echo "$old_streams" | tr ' ' '\n' | head -5
                if [[ $stream_count -gt 5 ]]; then
                    log_info "... and $((stream_count - 5)) more streams"
                fi
            else
                # Delete old log streams
                echo "$old_streams" | tr ' ' '\n' | while read -r stream_name; do
                    if [[ -n "$stream_name" ]]; then
                        aws logs delete-log-stream \
                            --log-group-name "$log_group" \
                            --log-stream-name "$stream_name" \
                            --region "$REGION" 2>/dev/null || true
                        log_debug "Deleted log stream: $stream_name"
                    fi
                done
                log_info "Deleted $stream_count old log streams from $log_group"
            fi
        else
            log_info "No old log streams found in $log_group"
        fi
    done
}

# Function to cleanup stack
cleanup_stack() {
    if [[ -z "$STACK_NAME" ]]; then
        log_info "No stack name provided, skipping stack cleanup"
        return 0
    fi
    
    log_info "Cleaning up stack: $STACK_NAME"
    
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        log_warn "Stack $STACK_NAME not found in region $REGION"
        return 0
    fi
    
    local stack_status=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].StackStatus' --output text)
    log_info "Current stack status: $stack_status"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would delete stack $STACK_NAME"
        log_info "Stack resources that would be deleted:"
        aws cloudformation describe-stack-resources \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query 'StackResources[*].[LogicalResourceId,ResourceType,PhysicalResourceId]' \
            --output table
        return 0
    fi
    
    if [[ "$FORCE" != true ]]; then
        log_warn "This will permanently delete the stack and all its resources."
        read -p "Are you sure you want to delete stack $STACK_NAME? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Stack deletion cancelled by user"
            return 0
        fi
    fi
    
    # Delete the stack
    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
    
    # Wait for deletion to complete
    log_info "Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
    
    log_info "Stack deleted successfully"
}

# Function to cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Cleanup old log files
    if [[ -d "$LOG_DIR" ]]; then
        log_info "Cleaning up log files older than $RETENTION_DAYS days..."
        
        local old_logs=$(find "$LOG_DIR" -name "*.log" -type f -mtime +$RETENTION_DAYS 2>/dev/null || echo "")
        
        if [[ -n "$old_logs" ]]; then
            local log_count=$(echo "$old_logs" | wc -l)
            log_info "Found $log_count old log files"
            
            if [[ "$DRY_RUN" == true ]]; then
                log_info "DRY RUN: Would delete the following log files:"
                echo "$old_logs" | head -5
                if [[ $log_count -gt 5 ]]; then
                    log_info "... and $((log_count - 5)) more files"
                fi
            else
                echo "$old_logs" | while read -r log_file; do
                    if [[ -f "$log_file" ]]; then
                        rm -f "$log_file"
                        log_debug "Deleted log file: $log_file"
                    fi
                done
                log_info "Deleted $log_count old log files"
            fi
        else
            log_info "No old log files found"
        fi
    fi
    
    # Cleanup old backup files
    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "Cleaning up backup files older than $RETENTION_DAYS days..."
        
        local old_backups=$(find "$BACKUP_DIR" -name "*.json" -type f -mtime +$RETENTION_DAYS 2>/dev/null || echo "")
        
        if [[ -n "$old_backups" ]]; then
            local backup_count=$(echo "$old_backups" | wc -l)
            log_info "Found $backup_count old backup files"
            
            if [[ "$DRY_RUN" == true ]]; then
                log_info "DRY RUN: Would delete the following backup files:"
                echo "$old_backups" | head -5
                if [[ $backup_count -gt 5 ]]; then
                    log_info "... and $((backup_count - 5)) more files"
                fi
            else
                echo "$old_backups" | while read -r backup_file; do
                    if [[ -f "$backup_file" ]]; then
                        rm -f "$backup_file"
                        log_debug "Deleted backup file: $backup_file"
                    fi
                done
                log_info "Deleted $backup_count old backup files"
            fi
        else
            log_info "No old backup files found"
        fi
    fi
    
    # Cleanup empty directories
    if [[ "$DRY_RUN" != true ]]; then
        find "$LOG_DIR" -type d -empty -delete 2>/dev/null || true
        find "$BACKUP_DIR" -type d -empty -delete 2>/dev/null || true
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary:"
    log_info "  Cleanup Type: $CLEANUP_TYPE"
    log_info "  Stack Name: ${STACK_NAME:-'N/A'}"
    log_info "  Region: $REGION"
    log_info "  Retention Days: $RETENTION_DAYS"
    log_info "  Dry Run: $DRY_RUN"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "This was a dry run - no resources were actually deleted"
    else
        log_info "Cleanup completed successfully"
    fi
}

# Main execution function
main() {
    local exit_code=0
    
    # Execute cleanup steps based on type
    check_prerequisites
    
    case "$CLEANUP_TYPE" in
        "all")
            get_stack_resources
            cleanup_s3_artifacts
            cleanup_cloudwatch_logs
            cleanup_stack
            cleanup_local_files
            ;;
        "stack-only")
            get_stack_resources
            cleanup_stack
            ;;
        "artifacts-only")
            get_stack_resources
            cleanup_s3_artifacts
            cleanup_cloudwatch_logs
            ;;
        "logs-only")
            cleanup_local_files
            ;;
    esac
    
    display_cleanup_summary
    log_header "Cleanup completed!"
    log_info "Log file: $LOG_FILE"
    
    return $exit_code
}

# Execute main function
main "$@"