# VPC Configuration Guide for CloudWatch Synthetics

This guide provides detailed instructions for configuring VPC networking to enable CloudWatch Synthetics canaries to access on-premises infrastructure.

## Overview

CloudWatch Synthetics canaries run in AWS-managed infrastructure but can be configured to run within your VPC to access private resources, including on-premises infrastructure through VPN or Direct Connect.

## Prerequisites

- Existing VPC with connectivity to on-premises infrastructure
- VPN Gateway or Direct Connect Gateway configured
- Understanding of your on-premises network topology
- Route tables configured for on-premises traffic

## VPC Architecture for Synthetics

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS VPC                              │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │   Private       │    │   Private       │                │
│  │   Subnet A      │    │   Subnet B      │                │
│  │                 │    │                 │                │
│  │ ┌─────────────┐ │    │ ┌─────────────┐ │                │
│  │ │   Canary    │ │    │ │   Canary    │ │                │
│  │ │ Execution   │ │    │ │ Execution   │ │                │
│  │ └─────────────┘ │    │ └─────────────┘ │                │
│  └─────────────────┘    └─────────────────┘                │
│           │                       │                        │
│  ┌─────────────────────────────────────────────────────────┤
│  │                Route Table                              │
│  │  - 0.0.0.0/0 → NAT Gateway (for AWS API access)        │
│  │  - 10.0.0.0/8 → VPN Gateway (on-premises)              │
│  │  - 172.16.0.0/12 → VPN Gateway (on-premises)           │
│  └─────────────────────────────────────────────────────────┤
└─────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────────────┐
                    │   VPN Gateway   │
                    │       or        │
                    │ Direct Connect  │
                    │    Gateway      │
                    └─────────────────┘
                              │
                    ┌─────────────────┐
                    │  On-Premises    │
                    │ Infrastructure  │
                    │                 │
                    │ ┌─────────────┐ │
                    │ │  Monitored  │ │
                    │ │  Endpoints  │ │
                    │ └─────────────┘ │
                    └─────────────────┘
```

## Step 1: Identify Network Requirements

### 1.1 Document On-Premises Network Details
Create a network inventory:

| Component | Details | Example |
|-----------|---------|---------|
| On-premises CIDR blocks | IP ranges to access | 10.1.0.0/16, 192.168.0.0/16 |
| Target endpoints | Specific IPs/ports to monitor | 10.1.1.100:8080, 192.168.1.50:443 |
| VPN/DX Gateway | Gateway for on-premises access | vgw-1234567890abcdef0 |
| DNS servers | On-premises DNS (if needed) | 10.1.1.10, 10.1.1.11 |

### 1.2 Verify Existing Connectivity
Test connectivity from existing VPC resources:
```bash
# From an EC2 instance in your VPC
ping 10.1.1.100
telnet 10.1.1.100 8080
nslookup your-onprem-hostname.local
```

## Step 2: Configure VPC Subnets

### 2.1 Identify Suitable Subnets
Requirements for canary subnets:
- **Private subnets** (recommended for security)
- **Multiple AZs** (for high availability)
- **Route to on-premises** via VPN/Direct Connect
- **Route to internet** via NAT Gateway (for AWS API access)

### 2.2 Create Dedicated Subnets (Optional)
If existing subnets don't meet requirements:

1. **Navigate to VPC Console**
2. **Click Subnets → Create subnet**
3. **Configure subnet details:**
   - **VPC**: Select your VPC
   - **Subnet name**: `canary-subnet-1a`
   - **Availability Zone**: us-east-1a
   - **IPv4 CIDR block**: 10.0.10.0/24
4. **Repeat for additional AZs**

### 2.3 Verify Subnet Route Tables
For each canary subnet, verify route table contains:

| Destination | Target | Purpose |
|-------------|--------|---------|
| 0.0.0.0/0 | NAT Gateway | AWS API access |
| 10.0.0.0/8 | VPN Gateway | On-premises access |
| 172.16.0.0/12 | VPN Gateway | On-premises access (if used) |
| 192.168.0.0/16 | VPN Gateway | On-premises access (if used) |

## Step 3: Create Security Groups

### 3.1 Create Canary Security Group
1. **Navigate to EC2 Console → Security Groups**
2. **Click Create security group**
3. **Basic details:**
   - **Name**: `synthetics-canary-sg`
   - **Description**: `Security group for CloudWatch Synthetics canaries`
   - **VPC**: Select your VPC

### 3.2 Configure Outbound Rules

#### Required Outbound Rules:

**Rule 1: AWS API Access**
- **Type**: HTTPS
- **Protocol**: TCP
- **Port range**: 443
- **Destination**: 0.0.0.0/0
- **Description**: AWS API and service access

**Rule 2: On-Premises HTTP Access**
- **Type**: HTTP
- **Protocol**: TCP
- **Port range**: 80
- **Destination**: [Your on-premises CIDR]
- **Description**: HTTP access to on-premises endpoints

**Rule 3: On-Premises HTTPS Access**
- **Type**: HTTPS
- **Protocol**: TCP
- **Port range**: 443
- **Destination**: [Your on-premises CIDR]
- **Description**: HTTPS access to on-premises endpoints

**Rule 4: Custom Port Access (if needed)**
- **Type**: Custom TCP
- **Protocol**: TCP
- **Port range**: [Your custom port, e.g., 8080]
- **Destination**: [Your on-premises CIDR]
- **Description**: Custom application port access

**Rule 5: DNS Resolution (if using on-premises DNS)**
- **Type**: DNS (UDP)
- **Protocol**: UDP
- **Port range**: 53
- **Destination**: [Your DNS server IPs]
- **Description**: DNS resolution for on-premises hostnames

### 3.3 Inbound Rules
- **No inbound rules required** for canaries
- Keep default (no inbound rules)

### 3.4 Example Security Group Configuration

```json
{
  "GroupName": "synthetics-canary-sg",
  "Description": "Security group for CloudWatch Synthetics canaries",
  "VpcId": "vpc-12345678",
  "SecurityGroupRules": [
    {
      "IpPermissions": [],
      "IpPermissionsEgress": [
        {
          "IpProtocol": "tcp",
          "FromPort": 443,
          "ToPort": 443,
          "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "AWS API access"}]
        },
        {
          "IpProtocol": "tcp",
          "FromPort": 80,
          "ToPort": 80,
          "IpRanges": [{"CidrIp": "10.1.0.0/16", "Description": "On-premises HTTP"}]
        },
        {
          "IpProtocol": "tcp",
          "FromPort": 443,
          "ToPort": 443,
          "IpRanges": [{"CidrIp": "10.1.0.0/16", "Description": "On-premises HTTPS"}]
        },
        {
          "IpProtocol": "tcp",
          "FromPort": 8080,
          "ToPort": 8080,
          "IpRanges": [{"CidrIp": "10.1.0.0/16", "Description": "Custom application port"}]
        }
      ]
    }
  ]
}
```

## Step 4: Configure Route Tables

### 4.1 Verify Existing Route Tables
1. **Navigate to VPC Console → Route Tables**
2. **Select route table associated with canary subnets**
3. **Review Routes tab**

### 4.2 Add On-Premises Routes (if missing)
If routes to on-premises networks are missing:

1. **Click Edit routes**
2. **Add route:**
   - **Destination**: 10.1.0.0/16 (your on-premises CIDR)
   - **Target**: Select your VPN Gateway or Direct Connect Gateway
3. **Save changes**

### 4.3 Verify Internet Access Route
Ensure route exists for AWS API access:
- **Destination**: 0.0.0.0/0
- **Target**: NAT Gateway (for private subnets) or Internet Gateway (for public subnets)

## Step 5: Test Network Connectivity

### 5.1 Create Test EC2 Instance
1. **Launch EC2 instance in same subnet as planned canaries**
2. **Use same security group as canaries**
3. **Connect via Session Manager or bastion host**

### 5.2 Test Connectivity Commands
```bash
# Test basic connectivity
ping -c 4 10.1.1.100

# Test specific ports
telnet 10.1.1.100 8080
nc -zv 10.1.1.100 443

# Test HTTP endpoints
curl -I http://10.1.1.100:8080/health
curl -I https://10.1.1.100/api/status

# Test DNS resolution (if using hostnames)
nslookup your-endpoint.onprem.local
dig your-endpoint.onprem.local

# Test AWS API access
aws sts get-caller-identity
```

### 5.3 Troubleshoot Connectivity Issues

**Issue: Cannot reach on-premises endpoints**
- Check route table has correct routes to VPN/DX Gateway
- Verify VPN/Direct Connect status
- Check on-premises firewall rules
- Verify security group outbound rules

**Issue: Cannot access AWS APIs**
- Check route to 0.0.0.0/0 via NAT Gateway
- Verify NAT Gateway is in public subnet
- Check Internet Gateway attachment to VPC

**Issue: DNS resolution fails**
- Check VPC DNS settings (enableDnsHostnames, enableDnsResolution)
- Verify DNS server accessibility
- Consider using IP addresses instead of hostnames

## Step 6: Configure VPC DNS Settings

### 6.1 Enable DNS Resolution
1. **Navigate to VPC Console**
2. **Select your VPC**
3. **Actions → Edit VPC settings**
4. **Enable DNS resolution**: ✓
5. **Enable DNS hostnames**: ✓
6. **Save changes**

### 6.2 Configure Custom DNS (if needed)
If using on-premises DNS servers:

1. **Create DHCP Options Set**
2. **Navigate to VPC Console → DHCP Options Sets**
3. **Create DHCP options set:**
   - **Domain name servers**: 10.1.1.10, 10.1.1.11, AmazonProvidedDNS
   - **Domain name**: your-domain.local
4. **Associate with VPC**

## Step 7: Security Considerations

### 7.1 Network Segmentation
- Use dedicated subnets for canaries
- Implement least-privilege security group rules
- Consider using VPC Flow Logs for monitoring

### 7.2 Access Control
- Restrict security group rules to specific IP ranges
- Use specific ports instead of "All Traffic" when possible
- Regularly review and audit security group rules

### 7.3 Monitoring and Logging
- Enable VPC Flow Logs
- Monitor CloudTrail for VPC configuration changes
- Set up CloudWatch alarms for unusual network activity

## Step 8: Validation Checklist

Before deploying canaries, verify:

- [ ] Subnets have routes to on-premises networks
- [ ] Subnets have routes to internet (for AWS API access)
- [ ] Security groups allow required outbound traffic
- [ ] VPN/Direct Connect connectivity is working
- [ ] DNS resolution works (if using hostnames)
- [ ] Test EC2 instance can reach target endpoints
- [ ] AWS API access works from test instance

## Common Network Configurations

### Configuration 1: Simple VPN Setup
```
VPC CIDR: 10.0.0.0/16
On-premises CIDR: 192.168.0.0/16
VPN Gateway: vgw-1234567890abcdef0

Route Table:
- 0.0.0.0/0 → NAT Gateway
- 192.168.0.0/16 → VPN Gateway
```

### Configuration 2: Multiple On-Premises Networks
```
VPC CIDR: 10.0.0.0/16
On-premises CIDRs: 
  - 10.1.0.0/16 (Data Center 1)
  - 10.2.0.0/16 (Data Center 2)
  - 192.168.0.0/16 (Branch Offices)

Route Table:
- 0.0.0.0/0 → NAT Gateway
- 10.1.0.0/16 → VPN Gateway
- 10.2.0.0/16 → VPN Gateway
- 192.168.0.0/16 → VPN Gateway
```

### Configuration 3: Direct Connect with VPN Backup
```
VPC CIDR: 10.0.0.0/16
On-premises CIDR: 172.16.0.0/12

Route Table:
- 0.0.0.0/0 → NAT Gateway
- 172.16.0.0/12 → Direct Connect Gateway (primary)
- 172.16.0.0/12 → VPN Gateway (backup, lower priority)
```

## Troubleshooting Guide

### Issue: Canary fails with "Network error"
**Symptoms**: Canary execution fails with network-related errors
**Solutions**:
1. Verify route table configuration
2. Check security group outbound rules
3. Test connectivity from EC2 instance in same subnet
4. Verify VPN/Direct Connect status

### Issue: Canary fails with "Timeout"
**Symptoms**: Canary times out when trying to reach endpoints
**Solutions**:
1. Check if endpoint is responsive
2. Verify network latency between AWS and on-premises
3. Increase canary timeout settings
4. Check for network congestion or packet loss

### Issue: Canary fails with "DNS resolution error"
**Symptoms**: Cannot resolve on-premises hostnames
**Solutions**:
1. Use IP addresses instead of hostnames
2. Configure custom DHCP options with on-premises DNS
3. Verify DNS server accessibility
4. Check VPC DNS settings

### Issue: High network costs
**Symptoms**: Unexpected charges for data transfer
**Solutions**:
1. Review canary frequency and data usage
2. Optimize canary scripts to minimize data transfer
3. Consider using VPC endpoints for AWS services
4. Monitor data transfer metrics

## Best Practices

1. **Use Private Subnets**: Deploy canaries in private subnets for security
2. **Multiple AZs**: Use subnets in multiple AZs for high availability
3. **Least Privilege**: Configure security groups with minimal required access
4. **Monitor Network Traffic**: Use VPC Flow Logs and CloudWatch metrics
5. **Regular Testing**: Periodically test network connectivity
6. **Documentation**: Maintain network diagrams and configuration documentation
7. **Change Management**: Use infrastructure as code for network changes

---

This VPC configuration guide ensures proper network setup for CloudWatch Synthetics canaries to access on-premises infrastructure securely and reliably.