# SSM Agent Manual Deployment Guide

This guide provides step-by-step manual instructions for installing and configuring AWS Systems Manager (SSM) Agent on on-premises VMs with CloudWatch monitoring. Each step can be executed individually, allowing you to understand and control every aspect of the deployment.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Phase 1: AWS Account Setup](#phase-1-aws-account-setup)
3. [Phase 2: VM Preparation](#phase-2-vm-preparation)
4. [Phase 3: SSM Agent Installation](#phase-3-ssm-agent-installation)
5. [Phase 4: Hybrid Activation](#phase-4-hybrid-activation)
6. [Phase 5: CloudWatch Monitoring](#phase-5-cloudwatch-monitoring)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Information
Gather the following information before starting:

```bash
# AWS Configuration
AWS_REGION="us-east-1"                    # Your preferred AWS region
AWS_ACCOUNT_ID="123456789012"             # Your 12-digit AWS account ID
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"  # AWS access key
AWS_SECRET_ACCESS_KEY="wJalrXUt..."       # AWS secret key

# Naming Configuration
INSTANCE_NAME_PREFIX="onprem"             # Prefix for your instances
SSM_ROLE_NAME="SSMServiceRole"            # IAM role name for SSM
```

### Required Permissions
Your AWS IAM user needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:GetRole",
        "iam:PutRolePolicy",
        "ssm:CreateActivation",
        "ssm:DescribeInstanceInformation",
        "ssm:ListActivations",
        "sns:CreateTopic",
        "sns:Subscribe",
        "sns:Publish",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Phase 1: AWS Account Setup

### Step 1.1: Configure AWS CLI Credentials

On your local machine or a management server:

```bash
# Option A: Configure AWS CLI profile
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter default region (e.g., us-east-1)
# Enter default output format (json)

# Option B: Use environment variables
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="us-east-1"
```

### Step 1.2: Create IAM Role for SSM

First, create the trust policy document:

```bash
# Create trust policy file
cat > ssm-trust-policy.json <<EOF
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
```

Create the IAM role:

```bash
# Create the role
aws iam create-role \
    --role-name SSMServiceRole \
    --assume-role-policy-document file://ssm-trust-policy.json \
    --description "Role for SSM managed on-premises instances"

# Attach the AWS managed policy
aws iam attach-role-policy \
    --role-name SSMServiceRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

Verify the role was created:

```bash
# Check role exists
aws iam get-role --role-name SSMServiceRole --query 'Role.RoleName' --output text
```

### Step 1.3: Create SNS Topic for Alerts

Create the SNS topic:

```bash
# Create SNS topic
aws sns create-topic \
    --name SSM-Alerts \
    --region us-east-1

# Save the Topic ARN from the output
# Example: arn:aws:sns:us-east-1:123456789012:SSM-Alerts
```

Subscribe your email to the topic:

```bash
# Subscribe email to topic
aws sns subscribe \
    --topic-arn arn:aws:sns:us-east-1:123456789012:SSM-Alerts \
    --protocol email \
    --notification-endpoint your-email@example.com

# Check your email and confirm the subscription
```

Verify the subscription:

```bash
# List subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn arn:aws:sns:us-east-1:123456789012:SSM-Alerts
```

---

## Phase 2: VM Preparation

### Step 2.1: Check VM Requirements

On each VM, verify the following:

```bash
# Check OS version
cat /etc/os-release

# Check architecture
uname -m

# Check if running as root or have sudo access
whoami

# Check internet connectivity
ping -c 2 amazonaws.com

# Check required ports (443 outbound)
nc -zv ssm.us-east-1.amazonaws.com 443
```

### Step 2.2: Install AWS CLI on VM (if needed)

For **Ubuntu/Debian**:

```bash
# Update package list
sudo apt-get update

# Install Python and pip
sudo apt-get install -y python3-pip curl wget

# Install AWS CLI
sudo pip3 install awscli

# Verify installation
aws --version
```

For **RHEL/CentOS/Rocky/AlmaLinux**:

```bash
# Install Python and pip
sudo yum install -y python3-pip curl wget

# Install AWS CLI
sudo pip3 install awscli

# Verify installation
aws --version
```

### Step 2.3: Configure AWS CLI on VM

```bash
# Configure AWS credentials on the VM
sudo aws configure
# OR use environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

---

## Phase 3: SSM Agent Installation

### Step 3.1: Download SSM Agent

For **Ubuntu/Debian (x86_64)**:

```bash
# Create temporary directory
sudo mkdir -p /tmp/ssm
cd /tmp/ssm

# Download SSM Agent
sudo wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb

# Install the package
sudo dpkg -i amazon-ssm-agent.deb
```

For **Ubuntu/Debian (ARM64)**:

```bash
# Create temporary directory
sudo mkdir -p /tmp/ssm
cd /tmp/ssm

# Download SSM Agent
sudo wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_arm64/amazon-ssm-agent.deb

# Install the package
sudo dpkg -i amazon-ssm-agent.deb
```

For **RHEL/CentOS/Rocky/AlmaLinux (x86_64)**:

```bash
# Install directly from S3
sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
```

For **RHEL/CentOS/Rocky/AlmaLinux (ARM64)**:

```bash
# Install directly from S3
sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_arm64/amazon-ssm-agent.rpm
```

For **Amazon Linux**:

```bash
# Install from repository
sudo yum install -y amazon-ssm-agent
```

### Step 3.2: Stop SSM Agent (for configuration)

```bash
# Stop the agent before configuration
sudo systemctl stop amazon-ssm-agent

# Verify it's stopped
sudo systemctl status amazon-ssm-agent
```

---

## Phase 4: Hybrid Activation

### Step 4.1: Create Hybrid Activation

From your management machine or AWS CloudShell:

```bash
# Set variables
ACTIVATION_NAME="hybrid-activation-$(date +%Y%m%d-%H%M%S)"
INSTANCE_NAME_PREFIX="onprem"
MAX_INSTANCES=100
EXPIRY_DAYS=30

# Calculate expiration date
EXPIRY_DATE=$(date -u -d "+${EXPIRY_DAYS} days" +"%Y-%m-%dT%H:%M:%S")

# Create activation
aws ssm create-activation \
    --default-instance-name "${INSTANCE_NAME_PREFIX}-$(hostname)" \
    --iam-role SSMServiceRole \
    --registration-limit ${MAX_INSTANCES} \
    --region us-east-1 \
    --expiration-date "${EXPIRY_DATE}" \
    --description "${ACTIVATION_NAME}" \
    --output json > activation.json

# Extract activation details
ACTIVATION_CODE=$(cat activation.json | grep -o '"ActivationCode": "[^"]*' | cut -d'"' -f4)
ACTIVATION_ID=$(cat activation.json | grep -o '"ActivationId": "[^"]*' | cut -d'"' -f4)

# Display activation details
echo "Activation Code: ${ACTIVATION_CODE}"
echo "Activation ID: ${ACTIVATION_ID}"
```

Save these values - you'll need them for each VM registration.

### Step 4.2: Register VM with Activation

On each VM:

```bash
# Use the activation code and ID from previous step
ACTIVATION_CODE="your-activation-code-here"
ACTIVATION_ID="your-activation-id-here"
AWS_REGION="us-east-1"

# Register the instance
sudo amazon-ssm-agent -register \
    -code "${ACTIVATION_CODE}" \
    -id "${ACTIVATION_ID}" \
    -region "${AWS_REGION}"

# Verify registration file was created
sudo cat /var/lib/amazon/ssm/registration
```

### Step 4.3: Start SSM Agent

```bash
# Enable the service to start on boot
sudo systemctl enable amazon-ssm-agent

# Start the service
sudo systemctl start amazon-ssm-agent

# Verify it's running
sudo systemctl status amazon-ssm-agent

# Check logs if needed
sudo tail -f /var/log/amazon/ssm/amazon-ssm-agent.log
```

### Step 4.4: Get Managed Instance ID

```bash
# Extract the managed instance ID
INSTANCE_ID=$(sudo cat /var/lib/amazon/ssm/registration | grep -o '"ManagedInstanceID":"[^"]*' | cut -d'"' -f4)
echo "Managed Instance ID: ${INSTANCE_ID}"

# Save this ID - you'll need it for CloudWatch alarms
```

---

## Phase 5: CloudWatch Monitoring

### Step 5.1: Create Instance-Specific Alarm

For each instance, create a specific alarm:

```bash
# Set variables
INSTANCE_ID="mi-1234567890abcdef0"  # From Step 4.4
HOSTNAME=$(hostname)
INSTANCE_NAME_PREFIX="onprem"
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:SSM-Alerts"

# Create instance-specific alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "SSM-Heartbeat-Failed-${INSTANCE_NAME_PREFIX}-${HOSTNAME}" \
    --alarm-description "SSM heartbeat lost for ${INSTANCE_NAME_PREFIX} instance: ${HOSTNAME} (${INSTANCE_ID})" \
    --metric-name "CommandsSucceeded" \
    --namespace "AWS/SSM-ManagedInstance" \
    --statistic "Sum" \
    --period 300 \
    --threshold 1 \
    --comparison-operator "LessThanThreshold" \
    --datapoints-to-alarm 2 \
    --evaluation-periods 2 \
    --treat-missing-data "breaching" \
    --dimensions "Name=InstanceId,Value=${INSTANCE_ID}" \
    --alarm-actions "${SNS_TOPIC_ARN}" \
    --region us-east-1
```

### Step 5.2: Create Fleet-Wide Alarm (Once Only)

Create this alarm only once for your entire fleet:

```bash
# Set variables
INSTANCE_NAME_PREFIX="onprem"
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:SSM-Alerts"

# Check if fleet alarm already exists
aws cloudwatch describe-alarms \
    --alarm-names "SSM-Heartbeat-Failed-${INSTANCE_NAME_PREFIX}-ANY" \
    --region us-east-1 \
    --query 'MetricAlarms[0].AlarmName' \
    --output text

# If it doesn't exist (returns "None"), create it:
aws cloudwatch put-metric-alarm \
    --alarm-name "SSM-Heartbeat-Failed-${INSTANCE_NAME_PREFIX}-ANY" \
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
    --alarm-actions "${SNS_TOPIC_ARN}" \
    --region us-east-1
```

### Step 5.3: Test CloudWatch Alarms

```bash
# List all SSM-related alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix "SSM-Heartbeat-Failed" \
    --region us-east-1 \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table

# Manually trigger an alarm for testing (optional)
aws cloudwatch set-alarm-state \
    --alarm-name "SSM-Heartbeat-Failed-${INSTANCE_NAME_PREFIX}-${HOSTNAME}" \
    --state-value ALARM \
    --state-reason "Testing alarm notification"
```

---

## Verification

### Step 6.1: Verify Instance in SSM Console

```bash
# Check if instance appears in SSM
aws ssm describe-instance-information \
    --region us-east-1 \
    --output table

# Get specific instance details
aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
    --region us-east-1 \
    --output json
```

### Step 6.2: Test SSM Connectivity

```bash
# Send a test command to the instance
aws ssm send-command \
    --instance-ids "${INSTANCE_ID}" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["echo Hello from SSM","hostname","date"]' \
    --region us-east-1 \
    --output json > command-output.json

# Get command ID
COMMAND_ID=$(cat command-output.json | grep -o '"CommandId": "[^"]*' | cut -d'"' -f4)

# Check command status
aws ssm get-command-invocation \
    --command-id "${COMMAND_ID}" \
    --instance-id "${INSTANCE_ID}" \
    --region us-east-1
```

### Step 6.3: Verify from VM

On the VM:

```bash
# Check SSM agent status
sudo systemctl status amazon-ssm-agent

# Check if instance is registered
sudo cat /var/lib/amazon/ssm/registration

# Check recent logs
sudo tail -50 /var/log/amazon/ssm/amazon-ssm-agent.log

# Check if agent is communicating
sudo tail -f /var/log/amazon/ssm/amazon-ssm-agent.log | grep -i "heartbeat"
```

---

## Troubleshooting

### Common Issues and Solutions

#### Instance Not Appearing in SSM Console

```bash
# 1. Check agent status
sudo systemctl status amazon-ssm-agent

# 2. Restart the agent
sudo systemctl restart amazon-ssm-agent

# 3. Check registration
sudo cat /var/lib/amazon/ssm/registration

# 4. Re-register if needed (use new activation)
sudo amazon-ssm-agent -register -code "NEW-CODE" -id "NEW-ID" -region "us-east-1"
sudo systemctl restart amazon-ssm-agent
```

#### Network Connectivity Issues

```bash
# Test connectivity to SSM endpoints
curl -I https://ssm.us-east-1.amazonaws.com
curl -I https://ssmmessages.us-east-1.amazonaws.com
curl -I https://ec2messages.us-east-1.amazonaws.com

# Check DNS resolution
nslookup ssm.us-east-1.amazonaws.com
nslookup ssmmessages.us-east-1.amazonaws.com

# Check firewall rules
sudo iptables -L -n | grep 443
```

#### CloudWatch Alarm Not Triggering

```bash
# Check alarm configuration
aws cloudwatch describe-alarms \
    --alarm-names "SSM-Heartbeat-Failed-${INSTANCE_NAME_PREFIX}-${HOSTNAME}" \
    --region us-east-1

# Check SNS subscription status
aws sns list-subscriptions-by-topic \
    --topic-arn "${SNS_TOPIC_ARN}"

# Test SNS topic directly
aws sns publish \
    --topic-arn "${SNS_TOPIC_ARN}" \
    --message "Test message from manual deployment" \
    --subject "SSM Alert Test"
```

#### Activation Expired or Limit Reached

```bash
# List existing activations
aws ssm describe-activations \
    --region us-east-1 \
    --output table

# Delete old activation if needed
aws ssm delete-activation \
    --activation-id "old-activation-id" \
    --region us-east-1

# Create new activation (repeat Step 4.1)
```

---

## Cleanup (Optional)

If you need to remove the SSM configuration:

### On the VM:

```bash
# Stop and disable SSM agent
sudo systemctl stop amazon-ssm-agent
sudo systemctl disable amazon-ssm-agent

# Remove SSM agent (Ubuntu/Debian)
sudo apt-get remove -y amazon-ssm-agent

# Remove SSM agent (RHEL/CentOS)
sudo yum remove -y amazon-ssm-agent

# Clean up registration
sudo rm -rf /var/lib/amazon/ssm/
```

### In AWS:

```bash
# Delete CloudWatch alarms
aws cloudwatch delete-alarms \
    --alarm-names "SSM-Heartbeat-Failed-${INSTANCE_NAME_PREFIX}-${HOSTNAME}" \
    --region us-east-1

# Delete activation (if no longer needed)
aws ssm delete-activation \
    --activation-id "${ACTIVATION_ID}" \
    --region us-east-1

# Delete IAM role (if no longer needed)
aws iam detach-role-policy \
    --role-name SSMServiceRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam delete-role --role-name SSMServiceRole

# Delete SNS topic (if no longer needed)
aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}"
```

---

## Summary Checklist

- [ ] AWS IAM role created (SSMServiceRole)
- [ ] SNS topic created and email subscribed
- [ ] AWS CLI installed on VM
- [ ] SSM Agent installed on VM
- [ ] Hybrid activation created
- [ ] VM registered with activation
- [ ] SSM Agent service running
- [ ] Instance visible in SSM console
- [ ] CloudWatch alarms created
- [ ] Email notifications tested

---

## Useful Commands Reference

```bash
# View all managed instances
aws ssm describe-instance-information --region us-east-1 --output table

# View all SSM activations
aws ssm describe-activations --region us-east-1 --output table

# View all CloudWatch alarms
aws cloudwatch describe-alarms --alarm-name-prefix "SSM-Heartbeat" --region us-east-1

# Check SSM agent version on instance
aws ssm send-command \
    --instance-ids "${INSTANCE_ID}" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["amazon-ssm-agent --version"]' \
    --region us-east-1

# Update SSM agent on instance
aws ssm send-command \
    --instance-ids "${INSTANCE_ID}" \
    --document-name "AWS-UpdateSSMAgent" \
    --region us-east-1
```

---

## Additional Resources

- [AWS Systems Manager Documentation](https://docs.aws.amazon.com/systems-manager/)
- [SSM Agent Installation Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html)
- [Hybrid Activations Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-managedinstances.html)
- [CloudWatch Alarms Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [SNS Documentation](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)