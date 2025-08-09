#!/bin/bash
# user-data.tpl - Template for automated instance configuration

set -e

# Logging setup
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=========================================="
echo "Snowball Monitor Setup Started: $(date)"
echo "=========================================="

# Update system packages
echo "Updating system packages..."
yum update -y

# Install required packages
echo "Installing required packages..."
yum install -y nc bc aws-cli cronie cronie-anacron

# Create monitoring user
echo "Creating monitoring user..."
useradd -m -s /bin/bash snowball-monitor

# Create directories
echo "Setting up directories..."
mkdir -p /opt/snowball-monitor/logs
chown -R snowball-monitor:snowball-monitor /opt/snowball-monitor

# Set up log rotation
echo "Configuring log rotation..."
cat > /etc/logrotate.d/snowball-monitor << 'LOGEOF'
/opt/snowball-monitor/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 snowball-monitor snowball-monitor
}
LOGEOF

# Enable and start cron
echo "Enabling cron service..."
systemctl enable crond
systemctl start crond

# Configure timezone
echo "Setting timezone..."
timedatectl set-timezone America/New_York

# Create the monitoring script with configuration
echo "Creating monitoring script..."
cat > /opt/snowball-monitor/snowball-monitor.sh << 'SCRIPTEOF'
#!/bin/bash
# Auto-generated monitoring script

# Configuration from Terraform
SNOWBALL_DEVICES=(
%{ for device in snowball_devices ~}
    "${device}"
%{ endfor ~}
)

SNOWBALL_PORT="8443"
TIMEOUT="5"
SNS_TOPIC="${sns_topic_arn}"

# State file for tracking previous status
STATE_FILE="/tmp/snowball-monitor-state.txt"

set -o pipefail

# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Global variables for tracking status
declare -A device_status
total_devices=$${#SNOWBALL_DEVICES[@]}
online_count=0
offline_count=0

# Function to print with timestamp and color
log_info() {
    echo -e "$${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:$${NC} $$1"
}

log_success() {
    echo -e "$${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:$${NC} $$1"
}

log_warning() {
    echo -e "$${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:$${NC} $$1"
}

log_error() {
    echo -e "$${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:$${NC} $$1"
}

# Function to send individual device metric
send_device_metric() {
    local device_ip=$$1
    local metric_value=$$2
    local status_text=$$3
    
    log_info "Sending metric for device $$device_ip: Status=$$metric_value"
    
    if aws cloudwatch put-metric-data \
        --namespace "Snowball/MultiDevice" \
        --metric-data MetricName=DeviceStatus,Value=$$metric_value,Unit=Count,Dimensions=[{Name=DeviceIP,Value=$$device_ip}] 2>/dev/null; then
        log_success "Device metric sent for $$device_ip ($$status_text)"
        return 0
    else
        log_error "Failed to send device metric for $$device_ip"
        return 1
    fi
}

# Function to send summary metrics
send_summary_metrics() {
    log_info "Sending summary metrics: $$online_count online, $$offline_count offline"
    
    local success=true
    
    if ! aws cloudwatch put-metric-data \
        --namespace "Snowball/MultiDevice" \
        --metric-data MetricName=TotalOnline,Value=$$online_count,Unit=Count 2>/dev/null; then
        log_error "Failed to send TotalOnline metric"
        success=false
    fi
    
    if ! aws cloudwatch put-metric-data \
        --namespace "Snowball/MultiDevice" \
        --metric-data MetricName=TotalOffline,Value=$$offline_count,Unit=Count 2>/dev/null; then
        log_error "Failed to send TotalOffline metric"
        success=false
    fi
    
    if ! aws cloudwatch put-metric-data \
        --namespace "Snowball/MultiDevice" \
        --metric-data MetricName=TotalDevices,Value=$$total_devices,Unit=Count 2>/dev/null; then
        log_error "Failed to send TotalDevices metric"
        success=false
    fi
    
    if $$success; then
        log_success "Summary metrics sent successfully"
    fi
    
    return $$($$success && echo 0 || echo 1)
}

# Function to get previous state
get_previous_state() {
    if [[ -f "$$STATE_FILE" ]]; then
        cat "$$STATE_FILE"
    else
        echo ""
    fi
}

# Function to save current state
save_current_state() {
    local offline_devices=()
    for device_ip in "$${SNOWBALL_DEVICES[@]}"; do
        if [[ $${device_status[$$device_ip]} -eq 0 ]]; then
            offline_devices+=("$$device_ip")
        fi
    done
    
    printf "%s" "$$(IFS=,; echo "$${offline_devices[*]}")" > "$$STATE_FILE"
}

# Function to send alert if status changed
send_alert_if_changed() {
    local current_offline=()
    for device_ip in "$${SNOWBALL_DEVICES[@]}"; do
        if [[ $${device_status[$$device_ip]} -eq 0 ]]; then
            current_offline+=("$$device_ip")
        fi
    done
    
    local current_state
    current_state=$$(IFS=,; echo "$${current_offline[*]}")
    
    local previous_state
    previous_state=$$(get_previous_state)
    
    if [[ "$$current_state" != "$$previous_state" ]]; then
        log_info "Device status changed, sending alert..."
        
        local message
        if [[ $${#current_offline[@]} -eq 0 ]]; then
            message="✅ SNOWBALL RECOVERY: All devices are now online as of $$(date '+%Y-%m-%d %H:%M:%S')"
            if [[ -n "$$previous_state" ]]; then
                message="$$message. Previously offline: $$previous_state"
            fi
        else
            message="❌ SNOWBALL ALERT: $${#current_offline[@]} of $$total_devices devices offline as of $$(date '+%Y-%m-%d %H:%M:%S')"
            message="$$message. Offline devices: $$(IFS=', '; echo "$${current_offline[*]}")"
        fi
        
        if aws sns publish --topic-arn "$$SNS_TOPIC" --message "$$message" --output text &>/dev/null; then
            log_success "Status change alert sent"
        else
            log_error "Failed to send status change alert"
        fi
        
        save_current_state
    else
        log_info "No status change detected, skipping alert"
    fi
}

# Function to check connectivity for a single device
check_device_connectivity() {
    local device_ip=$$1
    
    log_info "Checking connectivity to $$device_ip:$$SNOWBALL_PORT"
    
    local start_time=$$(date +%s.%N 2>/dev/null || date +%s)
    
    if timeout $$TIMEOUT nc -z -v $$device_ip $$SNOWBALL_PORT 2>&1; then
        local end_time=$$(date +%s.%N 2>/dev/null || date +%s)
        local duration=$$(echo "$$end_time - $$start_time" | bc -l 2>/dev/null || echo "N/A")
        
        log_success "✅ $$device_ip is reachable ($${duration}s)"
        device_status[$$device_ip]=1
        ((online_count++))
        return 0
    else
        local end_time=$$(date +%s.%N 2>/dev/null || date +%s)
        local duration=$$(echo "$$end_time - $$start_time" | bc -l 2>/dev/null || echo "N/A")
        
        log_error "❌ $$device_ip is UNREACHABLE ($${duration}s)"
        device_status[$$device_ip]=0
        ((offline_count++))
        return 1
    fi
}

# Function to check AWS CLI availability
check_aws_cli() {
    log_info "Checking AWS CLI configuration..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found."
        return 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured."
        return 1
    fi
    
    local aws_identity=$$(aws sts get-caller-identity --output text --query 'Account' 2>/dev/null)
    log_success "AWS CLI configured (Account: $$aws_identity)"
    return 0
}

# Function to display script header
show_header() {
    echo "================================================"
    echo "    Multi-Device Snowball Monitoring Script"
    echo "================================================"
    echo "Monitoring $${#SNOWBALL_DEVICES[@]} devices:"
    for device in "$${SNOWBALL_DEVICES[@]}"; do
        echo "  - $$device:$$SNOWBALL_PORT"
    done
    echo "SNS Topic: $${SNS_TOPIC##*/}"
    echo "Started: $$(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================"
    echo ""
}

# Function to show summary results
show_summary() {
    echo ""
    echo "================================================"
    echo "           MONITORING SUMMARY"
    echo "================================================"
    echo "Total Devices: $$total_devices"
    echo "Online: $$online_count"
    echo "Offline: $$offline_count"
    echo ""
    
    if [[ $$offline_count -gt 0 ]]; then
        echo "❌ OFFLINE DEVICES:"
        for device_ip in "$${SNOWBALL_DEVICES[@]}"; do
            if [[ $${device_status[$$device_ip]} -eq 0 ]]; then
                echo "  - $$device_ip"
            fi
        done
    else
        echo "✅ ALL DEVICES ONLINE"
    fi
    echo "================================================"
}

# Main execution
main() {
    show_header
    
    if [[ $${#SNOWBALL_DEVICES[@]} -eq 0 ]]; then
        log_error "No devices configured in SNOWBALL_DEVICES array"
        exit 1
    fi
    
    log_info "Performing pre-flight checks..."
    if ! check_aws_cli; then
        log_error "AWS CLI check failed - exiting"
        exit 1
    fi
    
    for tool in nc timeout; do
        if ! command -v $$tool &> /dev/null; then
            log_error "$$tool not found, this is required for connectivity testing"
            exit 1
        fi
    done
    
    if ! command -v bc &> /dev/null; then
        log_warning "bc not found, timing measurements may not work"
    fi
    
    echo ""
    log_info "=== STARTING CONNECTIVITY CHECKS ==="
    
    online_count=0
    offline_count=0
    
    for device_ip in "$${SNOWBALL_DEVICES[@]}"; do
        check_device_connectivity "$$device_ip" || true
        send_device_metric "$$device_ip" "$${device_status[$$device_ip]}" \
            "$$([ $${device_status[$$device_ip]} -eq 1 ] && echo "online" || echo "offline")" || true
    done
    
    echo ""
    log_info "=== SENDING SUMMARY METRICS ==="
    send_summary_metrics || log_warning "Some summary metrics failed to send"
    
    echo ""
    log_info "=== CHECKING FOR STATUS CHANGES ==="
    send_alert_if_changed || log_warning "Alert sending failed"
    
    show_summary
    
    if [[ $$offline_count -gt 0 ]]; then
        log_warning "Some devices are offline - exiting with error code"
        exit 1
    else
        log_success "All devices are online - exiting successfully"
        exit 0
    fi
}

# Trap to handle script interruption
trap 'log_warning "Script interrupted by user"; exit 130' INT TERM

# Run main function
main

echo ""
log_info "=== MONITORING CYCLE COMPLETE ==="
echo "Finished: $$(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
SCRIPTEOF

# Make script executable
chmod +x /opt/snowball-monitor/snowball-monitor.sh
chown snowball-monitor:snowball-monitor /opt/snowball-monitor/snowball-monitor.sh

# Create wrapper script for cron
echo "Creating cron wrapper script..."
cat > /opt/snowball-monitor/run-monitor.sh << 'WRAPPEREOF'
#!/bin/bash
SCRIPT_DIR="/opt/snowball-monitor"
LOG_DIR="$$SCRIPT_DIR/logs"
LOG_FILE="$$LOG_DIR/monitor-$$(date +%Y%m%d).log"

# Ensure log directory exists
mkdir -p "$$LOG_DIR"

# Run the monitoring script and log output
echo "=== Monitor run started at $$(date) ===" >> "$$LOG_FILE"
cd "$$SCRIPT_DIR"
./snowball-monitor.sh >> "$$LOG_FILE" 2>&1
EXIT_CODE=$$?
echo "=== Monitor run finished at $$(date) with exit code $$EXIT_CODE ===" >> "$$LOG_FILE"
echo "" >> "$$LOG_FILE"

exit $$EXIT_CODE
WRAPPEREOF

chmod +x /opt/snowball-monitor/run-monitor.sh
chown snowball-monitor:snowball-monitor /opt/snowball-monitor/run-monitor.sh

# Set up cron job
echo "Setting up cron job..."
cat > /tmp/snowball-cron << 'CRONEOF'
# Snowball monitoring every ${monitoring_interval} minutes
*/${monitoring_interval} * * * * /opt/snowball-monitor/run-monitor.sh
CRONEOF

sudo -u snowball-monitor crontab /tmp/snowball-cron
rm /tmp/snowball-cron

# Create maintenance script
echo "Creating maintenance script..."
cat > /opt/snowball-monitor/maintenance.sh << 'MAINTEOF'
#!/bin/bash
echo "=== Snowball Monitor Maintenance ==="
echo "Date: $$(date)"
echo ""

echo "Disk Usage:"
df -h /opt/snowball-monitor
echo ""

echo "Log Files:"
find /opt/snowball-monitor/logs -name "*.log" -exec ls -lh {} \;
echo ""

echo "Cron Service Status:"
systemctl is-active crond
echo ""

echo "Recent Cron Executions:"
grep snowball-monitor /var/log/cron | tail -5
echo ""

echo "AWS Connectivity Test:"
aws sts get-caller-identity --output table
echo ""

echo "=== Maintenance Complete ==="
MAINTEOF

chmod +x /opt/snowball-monitor/maintenance.sh
chown snowball-monitor:snowball-monitor /opt/snowball-monitor/maintenance.sh

# Run initial test
echo "Running initial test..."
sudo -u snowball-monitor /opt/snowball-monitor/run-monitor.sh

# Signal completion
echo "=========================================="
echo "Snowball Monitor Setup Completed: $(date)"
echo "=========================================="

# Create status file for validation
echo "Setup completed successfully at $(date)" > /opt/snowball-monitor/setup-status.txt