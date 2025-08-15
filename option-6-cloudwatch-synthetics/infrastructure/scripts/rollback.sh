#!/bin/bash

# Rollback Script for CloudWatch Synthetics Canary Monitoring
# This script provides rollback capabilities for failed deployments

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
BACKUP_FILE=""
ROLLBACK_TYPE="delete"  # delete, restore, or previous-version
FORCE=false
VERBOSE=false

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
    echo -e "${PURPLE}[ROLLBACK]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Rollback CloudWatch Synthetics Canary monitoring deployments.

OPTIONS:
    -s, --stack-name NAME       Stack name to rollback (required)
    -r, --region REGION         AWS region [default: us-east-1]
    -p, --profile PROFILE       AWS profile to use
    -b, --backup-file FILE      Specific backup file to restore from
    -t, --type TYPE             Rollback type (delete|restore|previous-version) [default: delete]
    -f, --force                 Force rollback without confirmation
    -v, --verbose               Enable verbose output
    -h, --help                  Show this help message

ROLLBACK TYPES:
    delete              Delete the current stack completely
    restore             Restore from a specific backup file
    previous-version    Rollback to the previous stack version (if available)

EXAMPLES:
    # Delete a failed stack
    $0 --stack-name my-canary-stack --type delete

    # Restore from a specific backup
    $0 --stack-name my-canary-stack --type restore --backup-file ./backups/stack-backup.json

    # Rollback to previous version
    $0 --stack-name my-canary-stack --type previous-version

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
        -b|--backup-file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        -t|--type)
            ROLLBACK_TYPE="$2"
            shift 2
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

# Validate required parameters
if [[ -z "$STACK_NAME" ]]; then
    log_error "Stack name is required. Use --stack-name option."
    show_usage
    exit 1
fi

# Validate rollback type
if [[ ! "$ROLLBACK_TYPE" =~ ^(delete|restore|previous-version)$ ]]; then
    log_error "Invalid rollback type: $ROLLBACK_TYPE"
    show_usage
    exit 1
fi

# Initialize logging
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/rollback-$(date '+%Y%m%d-%H%M%S').log"
touch "$LOG_FILE"

log_header "Starting CloudWatch Synthetics Canary Rollback"

# Set AWS profile if provided
if [[ -n "$PROFILE" ]]; then
    export AWS_PROFILE="$PROFILE"
    log_info "Using AWS profile: $PROFILE"
fi

# Set AWS region
export AWS_DEFAULT_REGION="$REGION"

log_info "Rollback Configuration:"
log_info "  Stack Name: $STACK_NAME"
log_info "  Region: $REGION"
log_info "  Rollback Type: $ROLLBACK_TYPE"
log_info "  Backup File: ${BACKUP_FILE:-'Auto-detect'}"
log_info "  Force: $FORCE"

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

# Function to check stack status
check_stack_status() {
    log_info "Checking stack status..."
    
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        log_error "Stack $STACK_NAME not found in region $REGION"
        exit 1
    fi
    
    local stack_status=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].StackStatus' --output text)
    log_info "Current stack status: $stack_status"
    
    case "$stack_status" in
        "CREATE_FAILED"|"UPDATE_FAILED"|"ROLLBACK_COMPLETE"|"UPDATE_ROLLBACK_COMPLETE")
            log_info "Stack is in a failed state, rollback is appropriate"
            ;;
        "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS"|"DELETE_IN_PROGRESS")
            log_error "Stack is currently in progress. Wait for operation to complete before rolling back."
            exit 1
            ;;
        "CREATE_COMPLETE"|"UPDATE_COMPLETE")
            log_warn "Stack is in a successful state. Are you sure you want to rollback?"
            if [[ "$FORCE" != true ]]; then
                read -p "Continue with rollback? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Rollback cancelled by user"
                    exit 0
                fi
            fi
            ;;
    esac
}

# Function to find backup file
find_backup_file() {
    if [[ -n "$BACKUP_FILE" ]]; then
        if [[ ! -f "$BACKUP_FILE" ]]; then
            log_error "Specified backup file not found: $BACKUP_FILE"
            exit 1
        fi
        log_info "Using specified backup file: $BACKUP_FILE"
        return 0
    fi
    
    # Auto-detect latest backup
    if [[ -f "$BACKUP_DIR/latest-backup.txt" ]]; then
        BACKUP_FILE=$(cat "$BACKUP_DIR/latest-backup.txt")
        if [[ -f "$BACKUP_FILE" ]]; then
            log_info "Found latest backup file: $BACKUP_FILE"
            return 0
        fi
    fi
    
    # Look for backup files matching the stack name
    local backup_pattern="$BACKUP_DIR/stack-backup-${STACK_NAME}-*.json"
    local latest_backup=$(ls -t $backup_pattern 2>/dev/null | head -n1)
    
    if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
        BACKUP_FILE="$latest_backup"
        log_info "Found backup file: $BACKUP_FILE"
        return 0
    fi
    
    log_warn "No backup file found for stack: $STACK_NAME"
    return 1
}

# Function to create pre-rollback backup
create_pre_rollback_backup() {
    log_info "Creating pre-rollback backup..."
    
    local backup_timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_file="$BACKUP_DIR/pre-rollback-backup-${STACK_NAME}-${backup_timestamp}.json"
    
    mkdir -p "$BACKUP_DIR"
    
    # Export current stack state
    {
        echo "=== STACK TEMPLATE ==="
        aws cloudformation get-template --stack-name "$STACK_NAME" --region "$REGION"
        echo ""
        echo "=== STACK DESCRIPTION ==="
        aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION"
        echo ""
        echo "=== STACK RESOURCES ==="
        aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --region "$REGION"
        echo ""
        echo "=== STACK EVENTS ==="
        aws cloudformation describe-stack-events --stack-name "$STACK_NAME" --region "$REGION" --max-items 50
    } > "$backup_file"
    
    log_info "Pre-rollback backup created: $backup_file"
}

# Function to delete stack
delete_stack() {
    log_info "Deleting stack: $STACK_NAME"
    
    if [[ "$FORCE" != true ]]; then
        log_warn "This will permanently delete the stack and all its resources."
        read -p "Are you sure you want to delete the stack? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Stack deletion cancelled by user"
            exit 0
        fi
    fi
    
    # Get list of resources before deletion for logging
    log_info "Resources to be deleted:"
    aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'StackResources[*].[LogicalResourceId,ResourceType,PhysicalResourceId]' \
        --output table | tee -a "$LOG_FILE"
    
    # Delete the stack
    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
    
    # Wait for deletion to complete
    log_info "Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
    
    log_info "Stack deleted successfully"
}

# Function to restore from backup
restore_from_backup() {
    if ! find_backup_file; then
        log_error "Cannot restore: no backup file available"
        exit 1
    fi
    
    log_info "Restoring stack from backup: $BACKUP_FILE"
    
    # Extract template from backup
    local temp_template="/tmp/restore-template-${STACK_NAME}.json"
    
    # Parse the backup file to extract the template
    if grep -q "=== STACK TEMPLATE ===" "$BACKUP_FILE"; then
        # Extract template section from backup
        sed -n '/=== STACK TEMPLATE ===/,/=== STACK DESCRIPTION ===/p' "$BACKUP_FILE" | \
        sed '1d;$d' | \
        jq '.TemplateBody' > "$temp_template"
    else
        # Assume the entire file is a template
        cp "$BACKUP_FILE" "$temp_template"
    fi
    
    if [[ ! -s "$temp_template" ]]; then
        log_error "Failed to extract template from backup file"
        exit 1
    fi
    
    # First delete the current stack if it exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        log_info "Deleting current stack before restore..."
        aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
        aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
    fi
    
    # Create stack from backup template
    log_info "Creating stack from backup template..."
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body "file://$temp_template" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    # Wait for creation to complete
    log_info "Waiting for stack restoration to complete..."
    aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION"
    
    # Cleanup temporary file
    rm -f "$temp_template"
    
    log_info "Stack restored successfully from backup"
}

# Function to rollback to previous version
rollback_to_previous_version() {
    log_info "Rolling back to previous stack version..."
    
    # Check if stack supports rollback
    local stack_status=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].StackStatus' --output text)
    
    if [[ "$stack_status" == "UPDATE_ROLLBACK_COMPLETE" ]]; then
        log_warn "Stack is already in rollback state"
        return 0
    fi
    
    if [[ "$stack_status" != "UPDATE_FAILED" ]]; then
        log_error "Stack must be in UPDATE_FAILED state to rollback to previous version"
        log_error "Current status: $stack_status"
        exit 1
    fi
    
    # Initiate rollback
    log_info "Initiating stack rollback..."
    aws cloudformation continue-update-rollback --stack-name "$STACK_NAME" --region "$REGION"
    
    # Wait for rollback to complete
    log_info "Waiting for rollback to complete..."
    aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$REGION"
    
    log_info "Stack rollback completed successfully"
}

# Function to verify rollback
verify_rollback() {
    log_info "Verifying rollback results..."
    
    case "$ROLLBACK_TYPE" in
        "delete")
            if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
                log_error "Stack still exists after deletion attempt"
                return 1
            else
                log_info "Stack successfully deleted"
            fi
            ;;
        "restore"|"previous-version")
            if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
                log_error "Stack not found after restoration"
                return 1
            fi
            
            local stack_status=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].StackStatus' --output text)
            if [[ "$stack_status" =~ (COMPLETE)$ ]]; then
                log_info "Stack successfully restored with status: $stack_status"
            else
                log_error "Stack restoration may have failed. Status: $stack_status"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# Function to display rollback results
display_results() {
    log_info "Rollback Results:"
    
    case "$ROLLBACK_TYPE" in
        "delete")
            log_info "Stack $STACK_NAME has been deleted from region $REGION"
            ;;
        "restore"|"previous-version")
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
            fi
            ;;
    esac
}

# Main execution function
main() {
    local exit_code=0
    
    # Execute rollback steps
    check_prerequisites
    check_stack_status
    create_pre_rollback_backup
    
    case "$ROLLBACK_TYPE" in
        "delete")
            delete_stack
            ;;
        "restore")
            restore_from_backup
            ;;
        "previous-version")
            rollback_to_previous_version
            ;;
    esac
    
    if verify_rollback; then
        display_results
        log_header "Rollback completed successfully!"
    else
        log_error "Rollback verification failed"
        exit_code=1
    fi
    
    log_info "Log file: $LOG_FILE"
    return $exit_code
}

# Execute main function
main "$@"