# Manual Deployment Checklist

Quick reference checklist for manually deploying CloudWatch Synthetics canaries via AWS Console.

## Pre-Deployment Checklist

- [ ] AWS account with appropriate permissions
- [ ] VPC with on-premises connectivity (VPN/Direct Connect)
- [ ] On-premises endpoints accessible and documented
- [ ] Email address for notifications ready

## Deployment Steps

### 1. S3 Bucket for Artifacts
- [ ] Create S3 bucket: `my-canary-artifacts-[suffix]`
- [ ] Enable versioning and encryption
- [ ] Note bucket name and region

### 2. IAM Role Creation
- [ ] Create role: `CloudWatchSyntheticsRole-[env]`
- [ ] Attach policy: `CloudWatchSyntheticsExecutionRolePolicy`
- [ ] Attach policy: `VPCAccessExecutionsRole` (if using VPC)
- [ ] Update trust policy for `synthetics.amazonaws.com`

### 3. VPC and Security Group
- [ ] Identify VPC and subnets with on-premises connectivity
- [ ] Create security group: `canary-security-group`
- [ ] Configure outbound rules:
  - [ ] HTTPS (443) to 0.0.0.0/0 (AWS APIs)
  - [ ] HTTP/HTTPS to on-premises CIDR
  - [ ] Custom ports as needed
- [ ] Verify route tables have on-premises routes

### 4. Create Heartbeat Canary
- [ ] Navigate to CloudWatch > Synthetics > Canaries
- [ ] Create canary: `heartbeat-canary-[env]`
- [ ] Select "Heartbeat monitoring" blueprint
- [ ] Configure endpoint URL
- [ ] Set runtime version (latest Node.js)
- [ ] Configure schedule (frequency)
- [ ] Set S3 bucket for artifacts
- [ ] Select IAM role
- [ ] Configure VPC settings:
  - [ ] Select VPC
  - [ ] Select subnets
  - [ ] Select security group
- [ ] Add environment variables if needed
- [ ] Create and verify canary starts

### 5. Create API Canary (Optional)
- [ ] Create second canary: `api-canary-[env]`
- [ ] Select "API canary" blueprint
- [ ] Configure API endpoint and method
- [ ] Follow same VPC/IAM configuration as heartbeat
- [ ] Create and verify canary starts

### 6. SNS Topic and Subscription
- [ ] Create SNS topic: `canary-alerts-[env]`
- [ ] Create email subscription
- [ ] Confirm subscription via email
- [ ] Note Topic ARN

### 7. CloudWatch Alarms
- [ ] Create alarm for heartbeat canary:
  - [ ] Metric: SuccessPercent
  - [ ] Condition: Lower than 100
  - [ ] Action: Send to SNS topic
- [ ] Create alarm for API canary (if applicable)
- [ ] Create duration alarm (optional):
  - [ ] Metric: Duration
  - [ ] Condition: Greater than threshold
- [ ] Name alarms descriptively

### 8. Verification
- [ ] Check canary status shows "Running"
- [ ] Verify recent successful executions
- [ ] Review canary logs in CloudWatch
- [ ] Test alarm by temporarily breaking endpoint
- [ ] Confirm email notification received
- [ ] Restore endpoint and verify recovery

### 9. Optional Enhancements
- [ ] Create CloudWatch dashboard
- [ ] Set up additional monitoring widgets
- [ ] Configure log insights queries
- [ ] Document configuration for team

## Quick Configuration Reference

### Common Environment Variables
```
TIMEOUT=30000
RETRIES=3
TARGET_ENDPOINT=http://10.1.1.100:8080
EXPECTED_STATUS=200
REQUEST_TIMEOUT=10000
```

### Security Group Rules Template
```
Outbound Rules:
- HTTPS (443) → 0.0.0.0/0 (AWS APIs)
- HTTP (80) → [ON_PREM_CIDR] (On-premises HTTP)
- HTTPS (443) → [ON_PREM_CIDR] (On-premises HTTPS)
- Custom TCP ([PORT]) → [ON_PREM_CIDR] (Custom ports)
```

### Alarm Thresholds
```
Success Rate: < 100% (any failure)
Duration: > 30000ms (30 seconds)
Evaluation Periods: 2
Datapoints to Alarm: 1
```

## Troubleshooting Quick Fixes

### Canary Always Fails
- [ ] Check VPC route tables
- [ ] Verify security group outbound rules
- [ ] Test connectivity from EC2 in same subnet
- [ ] Confirm on-premises endpoint is accessible

### No Alarm Notifications
- [ ] Confirm SNS subscription via email
- [ ] Check alarm configuration
- [ ] Verify SNS topic permissions

### High Costs
- [ ] Reduce canary frequency
- [ ] Adjust data retention period
- [ ] Review S3 storage costs

## Cost Optimization Settings

### Frequency Recommendations
- **Critical systems**: 1-5 minutes
- **Standard monitoring**: 5-15 minutes  
- **Development/testing**: 30+ minutes

### Data Retention
- **Production**: 31 days
- **Development**: 7-14 days

## Post-Deployment Actions

- [ ] Document configuration details
- [ ] Share access with team members
- [ ] Set up monitoring dashboards
- [ ] Schedule regular reviews
- [ ] Plan for automation migration (optional)

## Emergency Procedures

### Disable Canary
1. Navigate to CloudWatch > Synthetics
2. Select canary
3. Actions > Stop

### Disable Alarms
1. Navigate to CloudWatch > Alarms
2. Select alarm
3. Actions > Disable

### Emergency Contacts
- Document team contacts for alarm notifications
- Include escalation procedures
- Maintain on-call rotation information

---

**Note**: For detailed instructions, refer to the [Manual Deployment Guide](manual-deployment-guide.md) and [VPC Configuration Guide](vpc-configuration-guide.md).