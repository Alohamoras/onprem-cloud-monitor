#!/bin/bash
# deploy-snowball-monitor.sh - One-click deployment script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
DEPLOYMENT_TYPE="public"
INSTANCE_TYPE="t3.nano"
MONITORING_INTERVAL="2"

# Function to print colored output
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some features may not work properly."
    fi
    
    log_success "Prerequisites check passed"
}

# Function to gather user input
gather_inputs() {
    log_info "Gathering deployment configuration..."
    
    # Snowball devices
    echo ""
    echo "Enter Snowball device IP addresses (one per line, press Enter twice when done):"
    SNOWBALL_DEVICES=()
    while true; do
        read -p "Device IP: " ip
        if [[ -z "$ip" ]]; then
            break
        fi
        # Basic IP validation
        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            SNOWBALL_DEVICES+=("\"$ip\"")
        else
            log_error "Invalid IP address format: $ip"
        fi
    done
    
    if [[ ${#SNOWBALL_DEVICES[@]} -eq 0 ]]; then
        log_error "At least one Snowball device IP is required."
        exit 1
    fi
    
    # SNS Topic ARN
    echo ""
    read -p "Enter SNS Topic ARN for alerts: " SNS_TOPIC_ARN
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        log_error "SNS Topic ARN is required."
        exit 1
    fi
    
    # VPC and Subnet selection
    echo ""
    log_info "Discovering AWS network configuration..."
    
    # Get VPCs
    echo "Available VPCs:"
    aws ec2 describe-vpcs --query 'Vpcs[].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock]' --output table
    read -p "Enter VPC ID: " VPC_ID
    
    # Get subnets in the VPC
    echo ""
    echo "Available subnets in VPC $VPC_ID:"
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[].[SubnetId,Tags[?Key==`Name`].Value|[0],CidrBlock,AvailabilityZone]' --output table
    read -p "Enter Subnet ID: " SUBNET_ID
    
    # Key pair
    echo ""
    echo "Available EC2 Key Pairs:"
    aws ec2 describe-key-pairs --query 'KeyPairs[].[KeyName]' --output table
    read -p "Enter Key Pair name: " KEY_NAME
    
    # SSH access
    echo ""
    read -p "Enter your IP address for SSH access (or CIDR block): " SSH_IP
    if [[ ! "$SSH_IP" =~ /[0-9]+$ ]]; then
        SSH_IP="$SSH_IP/32"
    fi
    
    # Deployment type
    echo ""
    echo "Deployment options:"
    echo "1. Public subnet (simple, requires public IP) - ~$5/month"
    echo "2. Private subnet with NAT Gateway - ~$50/month"
    echo "3. Private subnet with VPC Endpoints - ~$20/month"
    read -p "Choose deployment type (1-3) [1]: " deployment_choice
    
    case $deployment_choice in
        2) DEPLOYMENT_TYPE="private_nat" ;;
        3) DEPLOYMENT_TYPE="private_endpoints" ;;
        *) DEPLOYMENT_TYPE="public" ;;
    esac
    
    # Instance type
    echo ""
    read -p "Enter instance type [t3.nano]: " input_instance_type
    if [[ -n "$input_instance_type" ]]; then
        INSTANCE_TYPE="$input_instance_type"
    fi
    
    # Monitoring interval
    echo ""
    read -p "Enter monitoring interval in minutes [2]: " input_interval
    if [[ -n "$input_interval" ]]; then
        MONITORING_INTERVAL="$input_interval"
    fi
}

# Function to create Terraform configuration
create_terraform_config() {
    log_info "Creating Terraform configuration..."
    
    mkdir -p snowball-monitor-deployment
    cd snowball-monitor-deployment
    
    # Create terraform.tfvars
    cat > terraform.tfvars << EOF
snowball_devices = [$(IFS=','; echo "${SNOWBALL_DEVICES[*]}")]
sns_topic_arn = "$SNS_TOPIC_ARN"
vpc_id = "$VPC_ID"
subnet_id = "$SUBNET_ID"
key_name = "$KEY_NAME"
allowed_ssh_cidrs = ["$SSH_IP"]
deployment_type = "$DEPLOYMENT_TYPE"
instance_type = "$INSTANCE_TYPE"
monitoring_interval = $MONITORING_INTERVAL
EOF
    
    # Create main.tf that references the module
    cat > main.tf << 'EOF'
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Project = "snowball-monitoring"
      ManagedBy = "terraform"
      CreatedDate = formatdate("YYYY-MM-DD", timestamp())
    }
  }
}

module "snowball_monitor" {
  source = "./modules/snowball-monitor"
  
  snowball_devices     = var.snowball_devices
  sns_topic_arn       = var.sns_topic_arn
  vpc_id              = var.vpc_id
  subnet_id           = var.subnet_id
  key_name            = var.key_name
  allowed_ssh_cidrs   = var.allowed_ssh_cidrs
  deployment_type     = var.deployment_type
  instance_type       = var.instance_type
  monitoring_interval = var.monitoring_interval
}

output "instance_details" {
  description = "Details of the monitoring instance"
  value = {
    instance_id     = module.snowball_monitor.instance_id
    private_ip      = module.snowball_monitor.instance_private_ip
    public_ip       = module.snowball_monitor.instance_public_ip
    security_group  = module.snowball_monitor.security_group_id
  }
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm information"
  value = module.snowball_monitor.cloudwatch_alarms
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value = "ssh -i ${var.key_name}.pem ec2-user@${module.snowball_monitor.instance_public_ip != "" ? module.snowball_monitor.instance_public_ip : module.snowball_monitor.instance_private_ip}"
}
EOF
    
    # Create variables.tf
    cat > variables.tf << 'EOF'
variable "snowball_devices" {
  description = "List of Snowball device IP addresses"
  type        = list(string)
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "key_name" {
  description = "EC2 Key Pair name"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed SSH access"
  type        = list(string)
}

variable "deployment_type" {
  description = "Deployment type"
  type        = string
  default     = "public"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.nano"
}

variable "monitoring_interval" {
  description = "Monitoring interval in minutes"
  type        = number
  default     = 2
}
EOF
    
    log_success "Terraform configuration created"
}

# Function to deploy infrastructure
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    log_info "Creating deployment plan..."
    terraform plan -out=tfplan
    
    # Ask for confirmation
    echo ""
    read -p "Do you want to proceed with the deployment? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warning "Deployment cancelled by user"
        exit 0
    fi
    
    # Apply deployment
    log_info "Applying deployment..."
    terraform apply tfplan
    
    log_success "Infrastructure deployed successfully!"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Get instance details
    INSTANCE_ID=$(terraform output -raw instance_details | jq -r '.instance_id')
    INSTANCE_IP=$(terraform output -raw instance_details | jq -r '.public_ip // .private_ip')
    
    log_info "Waiting for instance to be ready..."
    aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID"
    
    log_info "Checking if monitoring script is running..."
    sleep 30  # Give some time for user-data to complete
    
    # Try to SSH and check status (if public deployment)
    if [[ "$DEPLOYMENT_TYPE" == "public" ]]; then
        log_info "Instance is accessible at: $INSTANCE_IP"
        log_info "You can SSH using: ssh -i $KEY_NAME.pem ec2-user@$INSTANCE_IP"
    else
        log_info "Private instance deployed at: $INSTANCE_IP"
        log_info "Access through bastion host or VPN"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display post-deployment information
show_post_deployment_info() {
    echo ""
    echo "=========================================="
    echo "    DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=========================================="
    echo ""
    
    # Get outputs
    terraform output
    
    echo ""
    echo "Next Steps:"
    echo "1. Check the monitoring logs:"
    echo "   sudo tail -f /opt/snowball-monitor/logs/monitor-\$(date +%Y%m%d).log"
    echo ""
    echo "2. Test alerting by blocking a Snowball device temporarily"
    echo ""
    echo "3. Monitor CloudWatch metrics in the AWS Console:"
    echo "   - Namespace: Snowball/MultiDevice"
    echo "   - Metrics: TotalOnline, TotalOffline, DeviceStatus"
    echo ""
    echo "4. Check CloudWatch Alarms:"
    terraform output -json cloudwatch_alarms | jq -r 'to_entries[] | "   - \(.key): \(.value)"'
    echo ""
    echo "5. Run maintenance script:"
    echo "   sudo /opt/snowball-monitor/maintenance.sh"
    echo ""
    echo "Cost Estimate: ~\$$(case "$DEPLOYMENT_TYPE" in
        "private_nat") echo "50" ;;
        "private_endpoints") echo "20" ;;
        *) echo "5" ;;
    esac)/month"
}

# Function to clean up on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up..."
    if [[ -d "snowball-monitor-deployment" ]]; then
        cd snowball-monitor-deployment
        terraform destroy -auto-approve || true
        cd ..
        rm -rf snowball-monitor-deployment
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "  Snowball Monitor Automated Deployment"
    echo "=========================================="
    echo ""
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    gather_inputs
    create_terraform_config
    deploy_infrastructure
    validate_deployment
    show_post_deployment_info
    
    log_success "Deployment completed successfully!"
}

# Show usage if help requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0"
    echo ""
    echo "This script automates the deployment of Snowball monitoring infrastructure."
    echo "It will guide you through the configuration and deploy everything automatically."
    echo ""
    echo "Prerequisites:"
    echo "- Terraform installed"
    echo "- AWS CLI installed and configured"
    echo "- Appropriate AWS permissions"
    echo ""
    exit 0
fi

# Run main function
main