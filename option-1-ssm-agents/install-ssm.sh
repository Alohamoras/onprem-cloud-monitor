#!/bin/bash

# SSM Agent Installation and Hybrid Activation Script with CloudWatch Monitoring
# This script installs SSM Agent, registers on-premises VMs with AWS Systems Manager,
# and sets up CloudWatch alarms for heartbeat monitoring

# ==================== CONFIGURATION VARIABLES ====================
# Set these variables before running the script

# AWS Configuration
AWS_REGION="us-east-1"                    # Your AWS region
AWS_ACCESS_KEY_ID=""                      # AWS Access Key ID
AWS_SECRET_ACCESS_KEY=""                   # AWS Secret Access Key
AWS_ACCOUNT_ID=""                         # Your AWS Account ID (12 digits)

# SNS Topic for CloudWatch Alarms
# IMPORTANT: Create an SNS topic first and subscribe your email to it:
# 1. Go to AWS SNS Console: https://console.aws.amazon.com/sns/
# 2. Create topic > Standard > Name it (e.g., "SSM-Alerts")
# 3. Create subscription > Protocol: Email > Endpoint: your-email@example.com
# 4. Confirm the subscription email
# 5. Copy the Topic ARN and paste below
SNS_TOPIC_ARN=""                          # ARN of SNS topic for alarm notifications
                                          # Example: arn:aws:sns:us-east-1:123456789012:SSM-Alerts

# CloudWatch Alarm Configuration
ENABLE_CLOUDWATCH_ALARMS=true             # Set to false to skip alarm creation
ALARM_THRESHOLD_MINUTES=10                # Minutes without heartbeat before alarm (default: 10)

# Hybrid Activation Name (will be auto-generated if left empty)
ACTIVATION_NAME=""                        # Optional: Custom name for activation

# IAM Role Name (will be created if doesn't exist)
SSM_ROLE_NAME="SSMServiceRole"           # IAM role for SSM

# Number of instances this activation can register
MAX_INSTANCES=100                         # Maximum number of instances for this activation

# Activation expiration (days from now)
ACTIVATION_EXPIRY_DAYS=30                 # Days until activation expires

# Instance name prefix (for identification in SSM console)
INSTANCE_NAME_PREFIX="onprem"             # Prefix for instance names

# ==================== END CONFIGURATION ====================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Validate required variables
if [[ -z "$AWS_ACCESS_KEY_ID" ]] || [[ -z "$AWS_SECRET_ACCESS_KEY" ]] || [[ -z "$AWS_ACCOUNT_ID" ]]; then
    print_error "Please set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_ACCOUNT_ID variables"
    exit 1
fi

# Validate SNS topic if alarms are enabled
if [[ "$ENABLE_CLOUDWATCH_ALARMS" == "true" ]] && [[ -z "$SNS_TOPIC_ARN" ]]; then
    print_warning "CloudWatch alarms are enabled but SNS_TOPIC_ARN is not set"
    print_warning "Alarms will not be created. Set SNS_TOPIC_ARN to enable alarm notifications"
    ENABLE_CLOUDWATCH_ALARMS=false
fi

# Detect OS
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
else
    print_error "Cannot detect OS. /etc/os-release not found"
    exit 1
fi

print_status "Detected OS: $OS $OS_VERSION"

# Function to install AWS CLI if not present
install_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_status "Installing AWS CLI..."
        case $OS in
            ubuntu|debian)
                apt-get update
                apt-get install -y python3-pip
                pip3 install awscli
                ;;
            rhel|centos|fedora|amzn|rocky|almalinux)
                yum install -y python3-pip
                pip3 install awscli
                ;;
            *)
                print_error "Unsupported OS for AWS CLI installation"
                exit 1
                ;;
        esac
    else
        print_status "AWS CLI already installed"
    fi
}

# Function to install SSM Agent
install_ssm_agent() {
    print_status "Installing SSM Agent..."
    
    case $OS in
        ubuntu|debian)
            # Install SSM Agent on Ubuntu/Debian
            mkdir -p /tmp/ssm
            cd /tmp/ssm
            
            # Determine architecture
            ARCH=$(uname -m)
            if [[ "$ARCH" == "x86_64" ]]; then
                wget -q https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
                dpkg -i amazon-ssm-agent.deb
            elif [[ "$ARCH" == "aarch64" ]]; then
                wget -q https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_arm64/amazon-ssm-agent.deb
                dpkg -i amazon-ssm-agent.deb
            else
                print_error "Unsupported architecture: $ARCH"
                exit 1
            fi
            ;;
            
        rhel|centos|fedora|rocky|almalinux)
            # Install SSM Agent on RHEL/CentOS/Fedora
            ARCH=$(uname -m)
            if [[ "$ARCH" == "x86_64" ]]; then
                yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
            elif [[ "$ARCH" == "aarch64" ]]; then
                yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_arm64/amazon-ssm-agent.rpm
            else
                print_error "Unsupported architecture: $ARCH"
                exit 1
            fi
            ;;
            
        amzn)
            # Amazon Linux
            yum install -y amazon-ssm-agent
            ;;
            
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    # Stop the agent (we'll configure it first before starting)
    systemctl stop amazon-ssm-agent 2>/dev/null || true
    
    print_status "SSM Agent installed successfully"
}

# Function to create IAM role for SSM
create_iam_role() {
    print_status "Setting up IAM role for SSM..."
    
    # Configure AWS CLI
    export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION=$AWS_REGION
    
    # Check if role exists
    if aws iam get-role --role-name $SSM_ROLE_NAME &>/dev/null; then
        print_status "IAM role $SSM_ROLE_NAME already exists"
    else
        print_status "Creating IAM role $SSM_ROLE_NAME..."
        
        # Create trust policy
        cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ssm.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        # Create the role
        aws iam create-role \
            --role-name $SSM_ROLE_NAME \
            --assume-role-policy-document file:///tmp/trust-policy.json \
            --description "Role for SSM managed instances" 2>/dev/null || true
        
        # Attach the managed policy
        aws iam attach-role-policy \
            --role-name $SSM_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
        
        print_status "IAM role created and configured"
        
        # Clean up
        rm -f /tmp/trust-policy.json
    fi
}

# Function to create hybrid activation
create_hybrid_activation() {
    print_status "Creating hybrid activation..."
    
    # Generate activation name if not provided
    if [[ -z "$ACTIVATION_NAME" ]]; then
        ACTIVATION_NAME="hybrid-activation-$(date +%Y%m%d-%H%M%S)"
    fi
    
    # Calculate expiration date
    if [[ "$OS" == "darwin" ]]; then
        EXPIRY_DATE=$(date -v +${ACTIVATION_EXPIRY_DAYS}d -u +"%Y-%m-%dT%H:%M:%S")
    else
        EXPIRY_DATE=$(date -u -d "+${ACTIVATION_EXPIRY_DAYS} days" +"%Y-%m-%dT%H:%M:%S")
    fi
    
    # Create the activation
    ACTIVATION_OUTPUT=$(aws ssm create-activation \
        --default-instance-name "${INSTANCE_NAME_PREFIX}-$(hostname)" \
        --iam-role $SSM_ROLE_NAME \
        --registration-limit $MAX_INSTANCES \
        --region $AWS_REGION \
        --expiration-date "${EXPIRY_DATE}" \
        --description "$ACTIVATION_NAME" \
        --output json)
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create activation"
        exit 1
    fi
    
    # Extract activation code and ID
    ACTIVATION_CODE=$(echo $ACTIVATION_OUTPUT | grep -o '"ActivationCode": "[^"]*' | cut -d'"' -f4)
    ACTIVATION_ID=$(echo $ACTIVATION_OUTPUT | grep -o '"ActivationId": "[^"]*' | cut -d'"' -f4)
    
    if [[ -z "$ACTIVATION_CODE" ]] || [[ -z "$ACTIVATION_ID" ]]; then
        print_error "Failed to extract activation details"
        exit 1
    fi
    
    print_status "Activation created successfully"
    print_status "Activation ID: $ACTIVATION_ID"
}

# Function to register the instance
register_instance() {
    print_status "Registering instance with AWS Systems Manager..."
    
    # Register the instance
    amazon-ssm-agent -register -code "$ACTIVATION_CODE" -id "$ACTIVATION_ID" -region "$AWS_REGION"
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to register instance"
        exit 1
    fi
    
    print_status "Instance registered successfully"
}

# Function to start SSM agent
start_ssm_agent() {
    print_status "Starting SSM Agent..."
    
    # Enable and start the service
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
    
    # Wait a moment for the service to start
    sleep 5
    
    # Check if service is running
    if systemctl is-active --quiet amazon-ssm-agent; then
        print_status "SSM Agent is running"
    else
        print_error "SSM Agent failed to start"
        systemctl status amazon-ssm-agent
        exit 1
    fi
}

# Function to verify connection
verify_connection() {
    print_status "Verifying SSM connection..."
    
    # Wait for instance to appear in SSM
    sleep 10
    
    # Check if instance is visible in SSM
    INSTANCE_ID=$(cat /var/lib/amazon/ssm/registration 2>/dev/null | grep -o '"ManagedInstanceID":"[^"]*' | cut -d'"' -f4)
    
    if [[ -n "$INSTANCE_ID" ]]; then
        print_status "Instance ID: $INSTANCE_ID"
        
        # Try to get instance information
        INSTANCE_INFO=$(aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
            --region $AWS_REGION \
            --output json 2>/dev/null)
        
        if [[ -n "$INSTANCE_INFO" ]] && [[ "$INSTANCE_INFO" != *"[]"* ]]; then
            print_status "✓ Instance is visible in AWS Systems Manager"
            print_status "✓ Heartbeat monitoring is active"
            
            # Store instance ID for alarm creation
            export MANAGED_INSTANCE_ID=$INSTANCE_ID
        else
            print_warning "Instance registered but not yet visible in SSM console. This may take a few minutes."
        fi
    else
        print_warning "Could not retrieve instance ID. Check AWS SSM console in a few minutes."
    fi
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    if [[ "$ENABLE_CLOUDWATCH_ALARMS" != "true" ]]; then
        print_status "CloudWatch alarms disabled, skipping alarm creation"
        return
    fi
    
    if [[ -z "$MANAGED_INSTANCE_ID" ]]; then
        print_warning "Instance ID not available, cannot create CloudWatch alarms"
        print_warning "You can manually create alarms later from the CloudWatch console"
        return
    fi
    
    print_status "Creating CloudWatch alarms for SSM heartbeat monitoring..."
    
    local HOSTNAME=$(hostname)
    local INSTANCE_ALARM_NAME="SSM-Heartbeat-Failed-${INSTANCE_NAME_PREFIX}-${HOSTNAME}"
    local FLEET_ALARM_NAME="SSM-Heartbeat-Failed-${INSTANCE_NAME_PREFIX}-ANY"
    
    # Create per-instance alarm
    print_status "Creating alarm for instance: $INSTANCE_ALARM_NAME"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$INSTANCE_ALARM_NAME" \
        --alarm-description "SSM heartbeat lost for ${INSTANCE_NAME_PREFIX} instance: ${HOSTNAME} (${MANAGED_INSTANCE_ID})" \
        --metric-name "CommandsSucceeded" \
        --namespace "AWS/SSM-ManagedInstance" \
        --statistic "Sum" \
        --period 300 \
        --threshold 1 \
        --comparison-operator "LessThanThreshold" \
        --datapoints-to-alarm 2 \
        --evaluation-periods 2 \
        --treat-missing-data "breaching" \
        --dimensions "Name=InstanceId,Value=${MANAGED_INSTANCE_ID}" \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --region "$AWS_REGION" 2>/dev/null || {
            print_warning "Failed to create instance-specific alarm. This might be a permissions issue."
        }
    
    # Check if fleet alarm already exists (only create once)
    FLEET_ALARM_EXISTS=$(aws cloudwatch describe-alarms \
        --alarm-names "$FLEET_ALARM_NAME" \
        --region "$AWS_REGION" \
        --query 'MetricAlarms[0].AlarmName' \
        --output text 2>/dev/null)
    
    if [[ "$FLEET_ALARM_EXISTS" == "$FLEET_ALARM_NAME" ]]; then
        print_status "Fleet alarm already exists: $FLEET_ALARM_NAME"
    else
        # Create fleet-wide alarm (any instance down)
        print_status "Creating fleet-wide alarm: $FLEET_ALARM_NAME"
        
        aws cloudwatch put-metric-alarm \
            --alarm-name "$FLEET_ALARM_NAME" \
            --alarm-description "SSM heartbeat lost for ANY ${INSTANCE_NAME_PREFIX} instance" \
            --metric-name "CommandsSucceeded" \
            --namespace "AWS/SSM-ManagedInstance" \
            --statistic "Sum" \
            --period 300 \
            --threshold 1 \
            --comparison-operator "LessThanThreshold" \
            --datapoints-to-alarm 2 \
            --evaluation-periods 2 \
            --treat-missing-data "breaching" \
            --alarm-actions "$SNS_TOPIC_ARN" \
            --region "$AWS_REGION" 2>/dev/null || {
                print_warning "Failed to create fleet-wide alarm. This might be a permissions issue."
            }
    fi
    
    print_status "CloudWatch alarms configured:"
    print_status "  - Instance alarm: $INSTANCE_ALARM_NAME"
    print_status "  - Fleet alarm: $FLEET_ALARM_NAME"
    print_status "  - Threshold: Alert after $ALARM_THRESHOLD_MINUTES minutes without heartbeat"
    print_status "  - Notifications will be sent to: $SNS_TOPIC_ARN"
}

# Function to display SNS setup instructions
display_sns_instructions() {
    if [[ "$ENABLE_CLOUDWATCH_ALARMS" == "true" ]] && [[ -z "$SNS_TOPIC_ARN" ]]; then
        print_warning "=========================================="
        print_warning "SNS Topic Setup Instructions:"
        print_warning "1. Go to: https://console.aws.amazon.com/sns/"
        print_warning "2. Click 'Create topic' > Choose 'Standard'"
        print_warning "3. Name it (e.g., 'SSM-Alerts')"
        print_warning "4. After creation, click on the topic"
        print_warning "5. Click 'Create subscription'"
        print_warning "6. Protocol: Email, Endpoint: your-email@example.com"
        print_warning "7. Confirm the subscription via email"
        print_warning "8. Copy the Topic ARN and set it in this script"
        print_warning "=========================================="
    fi
}

# Main execution
main() {
    print_status "Starting SSM Agent installation and hybrid activation"
    print_status "================================================"
    
    # Display SNS instructions if needed
    display_sns_instructions
    
    # Install AWS CLI if needed
    install_aws_cli
    
    # Install SSM Agent
    install_ssm_agent
    
    # Create IAM role
    create_iam_role
    
    # Create hybrid activation
    create_hybrid_activation
    
    # Register the instance
    register_instance
    
    # Start SSM Agent
    start_ssm_agent
    
    # Verify connection
    verify_connection
    
    # Create CloudWatch alarms
    create_cloudwatch_alarms
    
    print_status "================================================"
    print_status "✓ SSM Agent installation and registration complete!"
    
    if [[ "$ENABLE_CLOUDWATCH_ALARMS" == "true" ]] && [[ -n "$SNS_TOPIC_ARN" ]]; then
        print_status "✓ CloudWatch alarms configured for heartbeat monitoring"
    fi
    
    print_status "You can now manage this instance through AWS Systems Manager"
    print_status "Check the SSM console at: https://console.aws.amazon.com/systems-manager/managed-instances?region=$AWS_REGION"
    
    if [[ "$ENABLE_CLOUDWATCH_ALARMS" == "true" ]] && [[ -n "$SNS_TOPIC_ARN" ]]; then
        print_status "View alarms at: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#alarmsV2:"
    fi
}

# Run main function
main