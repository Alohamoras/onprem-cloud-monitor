# Advanced Networking Guide for Snowball Monitor

This guide covers deployment options for private subnets and high-security environments where a public IP is not desired or allowed.

## Prerequisites

- You've read the main [Deployment Guide](./Deployment-Guide.md)
- Understanding of VPC networking concepts
- Existing VPC with private subnets

---

## Overview of Private Subnet Options

| Option | Cost/Month | Complexity | Security | Use Case |
|--------|------------|------------|----------|----------|
| **Public Subnet** | ~$5 | Low | Medium | Testing, Development |
| **Private + NAT Gateway** | ~$50 | Medium | High | Production with internet |
| **Private + VPC Endpoints** | ~$20 | High | Highest | High-security production |

---

## Option 1: Private Subnet with NAT Gateway

**✅ Best for:** Production environments with existing NAT Gateway infrastructure  
**💰 Cost:** ~$50/month (NAT Gateway is ~$45/month)  
**🔒 Security:** High - no public IP on instance

### Prerequisites
- Existing NAT Gateway in your VPC
- Route table directing `0.0.0.0/0` traffic to NAT Gateway
- Bastion host or VPN for SSH access

### Deployment Steps

#### 1. Verify NAT Gateway Setup
```bash
# Check if your private subnet has NAT Gateway routing
PRIVATE_SUBNET_ID="subnet-YOUR_PRIVATE_SUBNET"
aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$PRIVATE_SUBNET_ID" \
    --query 'RouteTables[].Routes[?GatewayId!=null]'

# Should show a route like: 0.0.0.0/0 -> nat-xxxxxxxxx
```

#### 2. Create Security Group for Private Deployment
```bash
aws ec2 create-security-group \
    --group-name SnowballMonitor-Private \
    --description "Snowball Monitor - Private Subnet" \
    --vpc-id vpc-YOUR_VPC_ID

# Allow SSH from bastion host or internal network
aws ec2 authorize-security-group-ingress \
    --group-id sg-YOUR_NEW_SG_ID \
    --protocol tcp \
    --port 22 \
    --source-group sg-YOUR_BASTION_SG_ID
    # OR use --cidr for VPN range: --cidr 10.0.0.0/8
```

#### 3. Launch Instance in Private Subnet
```bash
# Use the same IAM role from main deployment guide
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*" "Name=state,Values=available" \
    --query 'Images|sort_by(@, &CreationDate)[-1].ImageId' \
    --output text)

# Launch WITHOUT public IP
aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.nano \
    --key-name YOUR_KEY_PAIR \
    --security-group-ids sg-YOUR_PRIVATE_SG_ID \
    --subnet-id $PRIVATE_SUBNET_ID \
    --iam-instance-profile Name=SnowballMonitoringProfile \
    --no-associate-public-ip-address \
    --user-data file://user-data.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=SnowballMonitor-Private}]'
```

#### 4. Access and Configure
```bash
# SSH through bastion host
ssh -J ec2-user@BASTION_PUBLIC_IP ec2-user@PRIVATE_INSTANCE_IP -i your-key.pem

# Or if using VPN/Direct Connect
ssh -i your-key.pem ec2-user@PRIVATE_INSTANCE_IP

# Follow Steps 3-7 from main deployment guide
```

#### 5. Validation
```bash
# From the private instance, test connectivity
aws sts get-caller-identity
curl -I https://aws.amazon.com  # Should work through NAT
nc -zv YOUR_SNOWBALL_IP 8443
```

---

## Option 2: Private Subnet with VPC Endpoints

**✅ Best for:** High-security environments, compliance requirements  
**💰 Cost:** ~$20/month (VPC endpoints ~$15/month)  
**🔒 Security:** Highest - no internet gateway required

### Prerequisites
- Private subnet with no internet access
- Understanding of VPC endpoints
- Bastion host or VPN for access

### Step 1: Create VPC Endpoints

#### Required Endpoints
You need these VPC endpoints for the monitoring script to work:

1. **S3 Gateway Endpoint** (free) - for package downloads
2. **CloudWatch Interface Endpoint** - for metrics
3. **SNS Interface Endpoint** - for alerts  
4. **STS Interface Endpoint** - for identity verification

#### Create VPC Endpoint Security Group
```bash
VPC_ID="vpc-YOUR_VPC_ID"
PRIVATE_SUBNET_ID="subnet-YOUR_PRIVATE_SUBNET"

# Create security group for VPC endpoints
aws ec2 create-security-group \
    --group-name VPCEndpoints-SnowballMonitor \
    --description "VPC Endpoints for Snowball Monitor" \
    --vpc-id $VPC_ID

VPC_ENDPOINT_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=VPCEndpoints-SnowballMonitor" \
    --query 'SecurityGroups[0].GroupId' --output text)

# Allow HTTPS traffic from your monitor instances
aws ec2 authorize-security-group-ingress \
    --group-id $VPC_ENDPOINT_SG \
    --protocol tcp \
    --port 443 \
    --source-group sg-YOUR_MONITOR_SECURITY_GROUP
```

#### Create S3 Gateway Endpoint
```bash
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$PRIVATE_SUBNET_ID" \
    --query 'RouteTables[0].RouteTableId' --output text)

aws ec2 create-vpc-endpoint \
    --vpc-id $VPC_ID \
    --service-name com.amazonaws.YOUR-REGION.s3 \
    --vpc-endpoint-type Gateway \
    --route-table-ids $ROUTE_TABLE_ID
```

#### Create Interface Endpoints
```bash
# CloudWatch endpoint
aws ec2 create-vpc-endpoint \
    --vpc-id $VPC_ID \
    --service-name com.amazonaws.YOUR-REGION.monitoring \
    --vpc-endpoint-type Interface \
    --subnet-ids $PRIVATE_SUBNET_ID \
    --security-group-ids $VPC_ENDPOINT_SG \
    --private-dns-enabled

# SNS endpoint
aws ec2 create-vpc-endpoint \
    --vpc-id $VPC_ID \
    --service-name com.amazonaws.YOUR-REGION.sns \
    --vpc-endpoint-type Interface \
    --subnet-ids $PRIVATE_SUBNET_ID \
    --security-group-ids $VPC_ENDPOINT_SG \
    --private-dns-enabled

# STS endpoint
aws ec2 create-vpc-endpoint \
    --vpc-id $VPC_ID \
    --service-name com.amazonaws.YOUR-REGION.sts \
    --vpc-endpoint-type Interface \
    --subnet-ids $PRIVATE_SUBNET_ID \
    --security-group-ids $VPC_ENDPOINT_SG \
    --private-dns-enabled
```

### Step 2: Modified User Data for VPC Endpoints

```bash
# Create specialized user data that doesn't require internet
cat > user-data-vpc-endpoints.sh << 'EOF'
#!/bin/bash
# Modified user data for VPC endpoint deployment
# Install packages without requiring internet updates

# Install required packages (skip updates to avoid internet dependency)
yum install -y nc bc aws-cli cronie cronie-anacron --skip-broken

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

# Configure timezone
timedatectl set-timezone America/New_York
EOF
```

### Step 3: Launch Instance with VPC Endpoints

```bash
# Launch instance in private subnet with VPC endpoints
aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.nano \
    --key-name YOUR_KEY_PAIR \
    --security-group-ids sg-YOUR_MONITOR_SG_ID \
    --subnet-id $PRIVATE_SUBNET_ID \
    --iam-instance-profile Name=SnowballMonitoringProfile \
    --no-associate-public-ip-address \
    --user-data file://user-data-vpc-endpoints.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=SnowballMonitor-VPCEndpoints}]'
```

### Step 4: Validate VPC Endpoints

```bash
# SSH to instance (through bastion or VPN)
ssh -i your-key.pem ec2-user@PRIVATE_INSTANCE_IP

# Test VPC endpoint connectivity
nslookup monitoring.YOUR-REGION.amazonaws.com
nslookup sns.YOUR-REGION.amazonaws.com
nslookup sts.YOUR-REGION.amazonaws.com

# Test AWS service calls
aws sts get-caller-identity
aws cloudwatch list-metrics --max-items 1

# Should work without internet access
curl -I https://google.com  # Should FAIL (no internet)
```

---

## Troubleshooting Private Deployments

### NAT Gateway Issues

```bash
# Check route table configuration
aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=subnet-YOUR_SUBNET" \
    --query 'RouteTables[].Routes[]'

# Test internet connectivity
curl -I https://aws.amazon.com
curl -s https://checkip.amazonaws.com

# Check NAT Gateway status
aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=vpc-YOUR_VPC_ID"
```

### VPC Endpoint Issues

```bash
# Check VPC endpoint status
aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=vpc-YOUR_VPC_ID" \
    --query 'VpcEndpoints[].[ServiceName,State,VpcEndpointType]'

# Test DNS resolution through endpoints
dig monitoring.YOUR-REGION.amazonaws.com
dig sns.YOUR-REGION.amazonaws.com

# Check endpoint security groups
aws ec2 describe-security-groups --group-ids $VPC_ENDPOINT_SG

# Test specific service calls
aws monitoring list-metrics --max-items 1
aws sns list-topics
```

### General Private Subnet Debugging

```bash
# Check instance metadata (should show no public IP)
curl -s http://169.254.169.254/latest/meta-data/public-ipv4  # Should fail

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-YOUR_SG_ID

# Test Snowball connectivity (should still work)
nc -zv YOUR_SNOWBALL_IP 8443

# Check system logs
sudo journalctl -u crond -f
tail -f /opt/snowball-monitor/logs/monitor-$(date +%Y%m%d).log
```

---

## Cost Optimization Tips

### For NAT Gateway Deployments
- **Share NAT Gateways** across multiple applications
- **Schedule workloads** to minimize data transfer during peak hours
- **Monitor data transfer costs** in CloudWatch

### For VPC Endpoint Deployments
- **Consolidate endpoints** - one endpoint can serve multiple subnets
- **Use Gateway endpoints** where available (S3, DynamoDB) - they're free
- **Consider Regional vs AZ endpoints** based on your architecture

---

## Security Best Practices

### Network Security
- **Use least-privilege security groups** - only allow required ports
- **Implement NACLs** for additional network-level security
- **Regular security group audits** - remove unused rules

### Access Control
- **Use AWS Systems Manager Session Manager** instead of SSH where possible
- **Implement MFA** for bastion host access
- **Use AWS CloudTrail** to audit all API calls

### Monitoring
- **Enable VPC Flow Logs** to monitor network traffic
- **Set up CloudWatch alarms** for unusual network patterns
- **Regular access reviews** - ensure only authorized personnel have access

---

## Migration Path

### From Public to Private
1. **Test in parallel** - deploy private instance alongside public
2. **Validate functionality** - ensure all features work
3. **Update monitoring** - adjust alarms for new instance
4. **Cutover** - update DNS/references to new instance
5. **Cleanup** - terminate public instance

### From NAT to VPC Endpoints
1. **Create VPC endpoints** while keeping NAT Gateway
2. **Test connectivity** through endpoints
3. **Remove NAT Gateway routes** (test in maintenance window)
4. **Monitor for issues** and validate cost savings

---

## Advanced Configurations

### Multi-Region Deployments
```bash
# Create cross-region VPC endpoints if monitoring Snowballs in different regions
aws ec2 create-vpc-endpoint \
    --vpc-id $VPC_ID \
    --service-name com.amazonaws.us-west-2.monitoring \
    --vpc-endpoint-type Interface \
    --subnet-ids $PRIVATE_SUBNET_ID \
    --security-group-ids $VPC_ENDPOINT_SG
```

### High Availability
```bash
# Deploy monitoring instances in multiple AZs
# Use Application Load Balancer for health checks
# Implement automated failover with Route 53 health checks
```

This advanced guide provides production-ready deployment options while keeping the main guide simple for quick starts!