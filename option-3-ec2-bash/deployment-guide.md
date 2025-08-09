# Deployment Guide for Snowball Monitor

## Prerequisites

⚠️ **Network Requirements**: This script requires internet access to communicate with AWS services (CloudWatch, SNS). The default deployment uses a **public subnet with a public IP** for simplicity.

> 📖 **For private subnet deployments** (NAT Gateway or VPC Endpoints), see the [Advanced Networking Guide](./Advanced-Networking-Guide.md).

---

## Step 1: Create IAM Role for EC2 Instance

### Create IAM Policy for Snowball Monitoring
#### ⚠️ BE SURE TO CHANGE YOUR-SNS-ARN TO YOUR SNS ARN!

### AWS CLI Commands to Create Role
```bash
# Create policy file
cat > snowball-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CloudWatchMetrics",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        },
        {
            "Sid": "SNSPublish",
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "YOUR-SNS-ARN"
        },
        {
            "Sid": "GetCallerIdentity",
            "Effect": "Allow",
            "Action": [
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create IAM policy
aws iam create-policy \
    --policy-name SnowballMonitoringPolicy \
    --policy-document file://snowball-policy.json

# Create IAM role for EC2
aws iam create-role \
    --role-name SnowballMonitoringRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ec2.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'

# Get your account ID and attach policy to role
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam attach-role-policy \
    --role-name SnowballMonitoringRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/SnowballMonitoringPolicy

# Create instance profile
aws iam create-instance-profile \
    --instance-profile-name SnowballMonitoringProfile

# Add role to instance profile
aws iam add-role-to-instance-profile \
    --instance-profile-name SnowballMonitoringProfile \
    --role-name SnowballMonitoringRole
```

## Step 2: Launch EC2 Instance

### Instance Specifications
- **Instance Type**: `t3.nano` or `t3.micro` (sufficient for this script)
- **AMI**: Amazon Linux 2023 (latest)
- **VPC**: Your existing VPC
- **Subnet**: **Public subnet** (required for internet access)
- **Public IP**: **Enabled** (required for AWS service communication)
- **IAM Instance Profile**: `SnowballMonitoringProfile`
- **Security Group**: Allow SSH inbound, all outbound

### Launch Command
```bash
# Get latest Amazon Linux 2023 AMI ID
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*" "Name=state,Values=available" \
    --query 'Images|sort_by(@, &CreationDate)[-1].ImageId' \
    --output text)

# Create user data script
cat > user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y nc bc aws-cli cronie cronie-anacron

# Create monitoring user
useradd -m -s /bin/bash snowball-monitor

# Create directories
mkdir -p /opt/snowball-monitor/logs
chown -R snowball-monitor:snowball-monitor /opt/snowball-monitor

# Set up log rotation
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
systemctl enable crond
systemctl start crond

# Configure timezone (optional)
timedatectl set-timezone America/New_York
EOF

# Launch instance with PUBLIC IP (required for internet access)
aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.nano \
    --key-name YOUR_KEY_PAIR \
    --security-group-ids sg-YOUR_SECURITY_GROUP \
    --subnet-id subnet-YOUR_PUBLIC_SUBNET \
    --iam-instance-profile Name=SnowballMonitoringProfile \
    --associate-public-ip-address \
    --user-data file://user-data.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=SnowballMonitor}]'
```

### Security Group Requirements
```bash
# Create security group for the monitor instance
aws ec2 create-security-group \
    --group-name SnowballMonitor-SG \
    --description "Snowball Monitor Security Group" \
    --vpc-id vpc-YOUR_VPC_ID

# Allow SSH from your IP address only
aws ec2 authorize-security-group-ingress \
    --group-id sg-YOUR_NEW_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr YOUR_IP_ADDRESS/32

# Outbound rules: Allow all (default)
# The instance needs HTTPS access to AWS services
```

## Step 3: Deploy and Configure the Script

### SSH into the instance and set up the script:
```bash
# SSH to instance
ssh -i your-key.pem ec2-user@YOUR_INSTANCE_PUBLIC_IP

# Switch to root for setup
sudo su -

# Create the monitoring script
vi /opt/snowball-monitor/snowball-monitor.sh
# [Paste snowball-monitor.sh script content in this file]

# Update the configuration in the script:
# 1. Change YOUR-SNS-TOPIC-ARN to your actual SNS topic ARN
# 2. Update the SNOWBALL_DEVICES array with your device IPs

# Make script executable
chmod +x /opt/snowball-monitor/snowball-monitor.sh
chown snowball-monitor:snowball-monitor /opt/snowball-monitor/snowball-monitor.sh

# Create wrapper script for cron with logging
cat > /opt/snowball-monitor/run-monitor.sh << 'EOF'
#!/bin/bash
SCRIPT_DIR="/opt/snowball-monitor"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/monitor-$(date +%Y%m%d).log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Run the monitoring script and log output
echo "=== Monitor run started at $(date) ===" >> "$LOG_FILE"
cd "$SCRIPT_DIR"
./snowball-monitor.sh >> "$LOG_FILE" 2>&1
EXIT_CODE=$?
echo "=== Monitor run finished at $(date) with exit code $EXIT_CODE ===" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

exit $EXIT_CODE
EOF

chmod +x /opt/snowball-monitor/run-monitor.sh
chown snowball-monitor:snowball-monitor /opt/snowball-monitor/run-monitor.sh
```

## Step 4: Set Up Cron Job

### Configure cron for the snowball-monitor user:
```bash
# Switch to monitoring user
sudo -u snowball-monitor crontab -e

# Add one of these cron entries:

# Every 2 minutes (recommended)
*/2 * * * * /opt/snowball-monitor/run-monitor.sh

# Every 5 minutes (lighter load)
*/5 * * * * /opt/snowball-monitor/run-monitor.sh
```

### Verify cron is working:
```bash
# Check cron status
sudo systemctl status crond

# View cron logs
sudo tail -f /var/log/cron

# Check your monitoring logs
sudo tail -f /opt/snowball-monitor/logs/monitor-$(date +%Y%m%d).log
```

## Step 5: Create CloudWatch Alarms

### Multi-Device CloudWatch Alarm Setup Commands

```bash
# Replace YOUR-REGION, YOUR-ACCOUNT, and YOUR-TOPIC with your actual values

# 1. OVERALL HEALTH ALARM: Triggers when ANY device goes offline
aws cloudwatch put-metric-alarm \
    --alarm-name "Snowball-MultiDevice-AnyOffline" \
    --alarm-description "Alert when any Snowball device goes offline" \
    --metric-name TotalOffline \
    --namespace Snowball/MultiDevice \
    --statistic Maximum \
    --period 300 \
    --evaluation-periods 1 \
    --datapoints-to-alarm 1 \
    --threshold 0.5 \
    --comparison-operator GreaterThanThreshold \
    --alarm-actions arn:aws:sns:YOUR-REGION:YOUR-ACCOUNT:YOUR-TOPIC \
    --ok-actions arn:aws:sns:YOUR-REGION:YOUR-ACCOUNT:YOUR-TOPIC \
    --treat-missing-data breaching

# 2. MONITOR HEALTH ALARM: Triggers when monitoring script stops running
aws cloudwatch put-metric-alarm \
    --alarm-name "Snowball-MultiDevice-Monitor-NotReporting" \
    --alarm-description "Alert when multi-device monitoring script stops reporting" \
    --metric-name TotalDevices \
    --namespace Snowball/MultiDevice \
    --statistic SampleCount \
    --period 900 \
    --evaluation-periods 2 \
    --threshold 1 \
    --comparison-operator LessThanThreshold \
    --treat-missing-data breaching \
    --alarm-actions arn:aws:sns:YOUR-REGION:YOUR-ACCOUNT:YOUR-TOPIC

# 3. CRITICAL HEALTH ALARM: Triggers when ALL devices are offline
aws cloudwatch put-metric-alarm \
    --alarm-name "Snowball-MultiDevice-AllOffline-CRITICAL" \
    --alarm-description "CRITICAL: All Snowball devices are offline" \
    --metric-name TotalOnline \
    --namespace Snowball/MultiDevice \
    --statistic Maximum \
    --period 300 \
    --evaluation-periods 2 \
    --datapoints-to-alarm 2 \
    --threshold 0.5 \
    --comparison-operator LessThanThreshold \
    --alarm-actions arn:aws:sns:YOUR-REGION:YOUR-ACCOUNT:YOUR-CRITICAL-TOPIC \
    --treat-missing-data breaching
```

## Step 6: Testing and Verification

### Test the setup:
```bash
# Test script manually
sudo -u snowball-monitor /opt/snowball-monitor/snowball-monitor.sh

# Test cron wrapper
sudo -u snowball-monitor /opt/snowball-monitor/run-monitor.sh

# Check logs
tail -n 50 /opt/snowball-monitor/logs/monitor-$(date +%Y%m%d).log

# Test connectivity validation
aws sts get-caller-identity
nc -zv YOUR_SNOWBALL_IP 8443
```

### Monitor cron execution:
```bash
# Watch cron logs in real-time
sudo tail -f /var/log/cron

# Watch monitoring logs in real-time  
sudo tail -f /opt/snowball-monitor/logs/monitor-$(date +%Y%m%d).log

# Check last few cron executions
sudo grep snowball-monitor /var/log/cron | tail -10
```

## Step 7: Maintenance Scripts

### Create maintenance script:
```bash
cat > /opt/snowball-monitor/maintenance.sh << 'EOF'
#!/bin/bash
# Maintenance script for Snowball Monitor

echo "=== Snowball Monitor Maintenance ==="
echo "Date: $(date)"
echo ""

# Check disk usage
echo "Disk Usage:"
df -h /opt/snowball-monitor
echo ""

# Check log file sizes
echo "Log Files:"
find /opt/snowball-monitor/logs -name "*.log" -exec ls -lh {} \;
echo ""

# Check cron status
echo "Cron Service Status:"
systemctl is-active crond
echo ""

# Show recent cron jobs
echo "Recent Cron Executions:"
grep snowball-monitor /var/log/cron | tail -5
echo ""

# Check AWS connectivity
echo "AWS Connectivity Test:"
aws sts get-caller-identity --output table
echo ""

echo "=== Maintenance Complete ==="
EOF

chmod +x /opt/snowball-monitor/maintenance.sh
```

## Troubleshooting Commands

```bash
# Check if script is running
ps aux | grep snowball-monitor

# Check cron jobs for user
sudo -u snowball-monitor crontab -l

# Check system logs
sudo journalctl -u crond -f

# Test network connectivity to Snowball
nc -zv <snowball-ip> 8443

# Test internet connectivity
curl -I https://aws.amazon.com

# Check public IP assigned
curl -s https://checkip.amazonaws.com

# Check AWS permissions
aws sts get-caller-identity
aws cloudwatch put-metric-data --namespace "Test" --metric-data MetricName=Test,Value=1 --dry-run

# View full monitoring logs
less /opt/snowball-monitor/logs/monitor-$(date +%Y%m%d).log
```

---

## ⚠️ Important Notes

- **Public IP Required**: The instance needs a public IP to communicate with AWS services
- **Security**: The instance will be accessible from the internet - ensure your security group only allows SSH from trusted IPs
- **Cost**: ~$5/month for t3.nano + EBS + data transfer
- **Private Subnets**: If you need to deploy in a private subnet, see the [Advanced Networking Guide](./Advanced-Networking-Guide.md)

## Next Steps

1. Monitor the logs to ensure everything is working: `tail -f /opt/snowball-monitor/logs/monitor-$(date +%Y%m%d).log`
2. Test the alerting by temporarily blocking access to one of your Snowball devices
3. Consider setting up CloudWatch dashboards for visualization
4. For production deployments, review the [Advanced Networking Guide](./Advanced-Networking-Guide.md) for more secure options