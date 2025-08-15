#!/bin/bash

# Main Deployment Orchestrator Script for CloudWatch Synthetics Canary Monitoring
# This script orchestrates the complete deployment process with all automation features

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Import common functions if available
if [[ -f "$SCRIPT_DIR/common-functions.sh" ]]; then
    source "$SCRIPT_DIR/common-functions.sh"
fi

# Default values
DEPLOYMENT_TYPE="cloudformation"
ENVIRONMENT="dev"
REGION="us-east-1"
STACK_NAME=""
PROFILE=""
CONFIG_FILE=""
SKIP_VALIDATION=false
SKIP_BACKUP=false
SKIP_MONITORING=false
AUTO_ROLLBACK=true
DRY_RUN=false
FORCE=false
VERBOSE=false
CLEANUP_ON_FAILURE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

log_header() {
    echo -e "${PURPLE}[DEPLOY]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Complete deployment orchestration for CloudWatch Synthetics Canary monitoring.

OPTIONS:
    -t, --type TYPE             Deployment type (cloudformation|cdk) [default: cloudformation]
    -e, --environment ENV       Environment name (dev, staging, prod) [default: dev]
    -r, --region REGION         AWS region [default: us-east-1]
    -s, --stack-name NAME       Custom stack name (auto-generated if not provided)
    -p, --profile PROFILE       AWS profile to use
    -c, --config FILE           Configuration file with deployment parameters
    --skip-validation           Skip pre-deployment parameter validation
    --skip-backup               Skip backup of existing resources
    --skip-monitoring           Skip deployment status monitoring
    --no-rollback               Disable automatic rollback on failure
    --cleanup-on-failure        Clean up resources if deployment fails
    --dry-run                   Perform validation and show what would be deployed
    -f, --force                 Force deployment even if validation warnings exist
    -v, --verbose               Enable verbose output
    -h, --help                  Show this help message

EXAMPLES:
    # Deploy to development environment
    $0 --environment dev --config ./config/dev.json

    # Deploy to production with CDK
    $0 --type cdk --environment prod --config ./config/prod.json

    # Dry run deployment
    $0 --dry-run --config ./config/staging.json

    # Deploy with custom stack name and monitoring
    $0 --stack-name my-custom-stack --config ./config/prod.json

    # Deploy with cleanup on failure
    $0 --environment prod --config ./config/prod.json --cleanup-on-failure

WORKFLOW:
    1. Parameter validation (unless --skip-validation)
    2. Pre-deployment checks
    3. Resource backup (unless --skip-backup)
    4. Deployment execution
    5. Status monitoring (unless --skip-monitoring)
    6. Rollback on failure (unless --no-rollback)
    7. Cleanup on failure (if --cleanup-on-failure)

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
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --skip-monitoring)
            SKIP_MONITORING=true
            shift
            ;;
        --no-rollback)
            AUTO_ROLLBACK=false
            shift
            ;;
        --cleanup-on-failure)
            CLEANUP_ON_FAILURE=true
            shift
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

# Generate stack name if not provided
if [[ -z "$STACK_NAME" ]]; then
    if [[ "$DEPLOYMENT_TYPE" == "cdk" ]]; then
        STACK_NAME="CanaryInfrastructureStack-${ENVIRONMENT}"
    else
        STACK_NAME="cloudwatch-synthetics-monitoring-${ENVIRONMENT}"
    fi
fi

log_header "CloudWatch Synthetics Canary Deployment Orchestration"
log_info "Deployment Configuration:"
log_info "  Type: $DEPLOYMENT_TYPE"
log_info "  Environment: $ENVIRONMENT"
log_info "  Region: $REGION"
log_info "  Stack Name: $STACK_NAME"
log_info "  Config File: ${CONFIG_FILE:-'Environment variables'}"
log_info "  Dry Run: $DRY_RUN"

# Function to run parameter validation
run_parameter_validation() {
    if [[ "$SKIP_VALIDATION" == true ]]; then
        log_warn "Skipping parameter validation"
        return 0
    fi
    
    log_info "Running parameter validation..."
    
    local validation_args=()
    
    if [[ -n "$CONFIG_FILE" ]]; then
        validation_args+=("--config" "$CONFIG_FILE")
    else
        log_error "Configuration file is required for validation"
        return 1
    fi
    
    validation_args+=("--region" "$REGION")
    
    if [[ -n "$PROFILE" ]]; then
        validation_args+=("--profile" "$PROFILE")
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        validation_args+=("--verbose")
    fi
    
    if [[ "$FORCE" == true ]]; then
        validation_args+=("--output" "text")
    else
        validation_args+=("--strict" "--output" "text")
    fi
    
    if "$SCRIPT_DIR/validate-parameters.sh" "${validation_args[@]}"; then
        log_info "Parameter validation passed"
        return 0
    else
        log_error "Parameter validation failed"
        if [[ "$FORCE" != true ]]; then
            log_error "Use --force to proceed despite validation errors"
            return 1
        else
            log_warn "Proceeding with deployment despite validation errors (--force specified)"
            return 0
        fi
    fi
}

# Function to run deployment automation
run_deployment() {
    log_info "Running deployment automation..."
    
    local deploy_args=()
    
    deploy_args+=("--type" "$DEPLOYMENT_TYPE")
    deploy_args+=("--environment" "$ENVIRONMENT")
    deploy_args+=("--region" "$REGION")
    deploy_args+=("--stack-name" "$STACK_NAME")
    
    if [[ -n "$PROFILE" ]]; then
        deploy_args+=("--profile" "$PROFILE")
    fi
    
    if [[ -n "$CONFIG_FILE" ]]; then
        deploy_args+=("--config" "$CONFIG_FILE")
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        deploy_args+=("--dry-run")
    fi
    
    if [[ "$SKIP_VALIDATION" == true ]]; then
        deploy_args+=("--skip-validation")
    fi
    
    if [[ "$SKIP_BACKUP" == true ]]; then
        deploy_args+=("--skip-backup")
    fi
    
    if [[ "$AUTO_ROLLBACK" == false ]]; then
        deploy_args+=("--no-rollback")
    fi
    
    if [[ "$FORCE" == true ]]; then
        deploy_args+=("--force")
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        deploy_args+=("--verbose")
    fi
    
    if "$SCRIPT_DIR/deploy-automation.sh" "${deploy_args[@]}"; then
        log_info "Deployment completed successfully"
        return 0
    else
        log_error "Deployment failed"
        return 1
    fi
}

# Function to run deployment monitoring
run_deployment_monitoring() {
    if [[ "$SKIP_MONITORING" == true || "$DRY_RUN" == true ]]; then
        log_warn "Skipping deployment monitoring"
        return 0
    fi
    
    log_info "Starting deployment monitoring..."
    
    local monitor_args=()
    
    monitor_args+=("--stack-name" "$STACK_NAME")
    monitor_args+=("--region" "$REGION")
    monitor_args+=("--type" "deployment")
    
    if [[ -n "$PROFILE" ]]; then
        monitor_args+=("--profile" "$PROFILE")
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        monitor_args+=("--verbose")
    fi
    
    # Run monitoring in background and capture PID
    "$SCRIPT_DIR/monitor-deployment.sh" "${monitor_args[@]}" &
    local monitor_pid=$!
    
    log_info "Deployment monitoring started (PID: $monitor_pid)"
    
    # Wait for monitoring to complete or timeout
    local timeout=1800  # 30 minutes
    local elapsed=0
    local interval=30
    
    while kill -0 $monitor_pid 2>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            log_warn "Monitoring timeout reached, stopping monitor"
            kill $monitor_pid 2>/dev/null || true
            break
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    # Check monitoring result
    if wait $monitor_pid 2>/dev/null; then
        log_info "Deployment monitoring completed successfully"
        return 0
    else
        log_error "Deployment monitoring detected issues"
        return 1
    fi
}

# Function to handle deployment failure
handle_deployment_failure() {
    log_error "Deployment failed, initiating failure handling..."
    
    # Run rollback if enabled
    if [[ "$AUTO_ROLLBACK" == true ]]; then
        log_info "Running automatic rollback..."
        
        local rollback_args=()
        rollback_args+=("--stack-name" "$STACK_NAME")
        rollback_args+=("--region" "$REGION")
        rollback_args+=("--type" "delete")
        rollback_args+=("--force")
        
        if [[ -n "$PROFILE" ]]; then
            rollback_args+=("--profile" "$PROFILE")
        fi
        
        if [[ "$VERBOSE" == true ]]; then
            rollback_args+=("--verbose")
        fi
        
        if "$SCRIPT_DIR/rollback.sh" "${rollback_args[@]}"; then
            log_info "Rollback completed successfully"
        else
            log_error "Rollback failed"
        fi
    fi
    
    # Run cleanup if enabled
    if [[ "$CLEANUP_ON_FAILURE" == true ]]; then
        log_info "Running cleanup after failure..."
        
        local cleanup_args=()
        cleanup_args+=("--stack-name" "$STACK_NAME")
        cleanup_args+=("--region" "$REGION")
        cleanup_args+=("--type" "all")
        cleanup_args+=("--force")
        
        if [[ -n "$PROFILE" ]]; then
            cleanup_args+=("--profile" "$PROFILE")
        fi
        
        if [[ "$VERBOSE" == true ]]; then
            cleanup_args+=("--verbose")
        fi
        
        if "$SCRIPT_DIR/cleanup.sh" "${cleanup_args[@]}"; then
            log_info "Cleanup completed successfully"
        else
            log_error "Cleanup failed"
        fi
    fi
}

# Function to display deployment summary
display_deployment_summary() {
    log_header "Deployment Summary"
    log_info "Stack Name: $STACK_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "Region: $REGION"
    log_info "Deployment Type: $DEPLOYMENT_TYPE"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "Status: DRY RUN COMPLETED"
    else
        # Check final stack status
        if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
            local stack_status=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].StackStatus' --output text)
            log_info "Final Status: $stack_status"
            
            if [[ "$stack_status" =~ (COMPLETE)$ ]]; then
                log_info "Deployment completed successfully!"
                
                # Display stack outputs
                log_info "Stack Outputs:"
                aws cloudformation describe-stacks \
                    --stack-name "$STACK_NAME" \
                    --region "$REGION" \
                    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
                    --output table 2>/dev/null || log_warn "No outputs available"
            else
                log_error "Deployment may have failed or is still in progress"
            fi
        else
            log_warn "Stack not found or not accessible"
        fi
    fi
    
    log_info "Deployment orchestration completed"
}

# Signal handler for graceful shutdown
cleanup_on_signal() {
    log_warn "Deployment interrupted by user"
    
    # Kill any background monitoring processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    display_deployment_summary
    exit 130
}

trap cleanup_on_signal SIGINT SIGTERM

# Main execution function
main() {
    local exit_code=0
    local deployment_success=false
    
    # Step 1: Parameter validation
    if ! run_parameter_validation; then
        exit_code=1
        log_error "Parameter validation failed, aborting deployment"
        return $exit_code
    fi
    
    # Step 2: Run deployment
    if run_deployment; then
        deployment_success=true
        log_info "Deployment phase completed successfully"
    else
        exit_code=1
        log_error "Deployment phase failed"
    fi
    
    # Step 3: Monitor deployment (only if deployment succeeded and not dry run)
    if [[ "$deployment_success" == true && "$DRY_RUN" != true ]]; then
        if ! run_deployment_monitoring; then
            exit_code=1
            deployment_success=false
            log_error "Deployment monitoring detected issues"
        fi
    fi
    
    # Step 4: Handle failure if needed
    if [[ "$deployment_success" != true && "$DRY_RUN" != true ]]; then
        handle_deployment_failure
    fi
    
    # Step 5: Display summary
    display_deployment_summary
    
    return $exit_code
}

# Execute main function
main "$@"