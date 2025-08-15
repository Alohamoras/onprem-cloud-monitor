# Manual Deployment Guide - AWS Console

This guide provides detailed step-by-step instructions for manually deploying CloudWatch Synthetics canaries using the AWS Console. This approach is ideal for learning the service, testing configurations, or when automated deployment tools are not available.

## Prerequisites

Before starting the manual deployment:

- AWS account with appropriate permissions
- VPC configured with connectivity to on-premises infrastructure
- On-premises endpoints accessible via VPN or Direct Connect
- Email address for alarm notifications
- Basic understanding of AWS networking concepts

## Required IAM Permissions

Ensure your user/role has the following permissions:
- `synthetics:*`
- `cloudwatch:*`
- `sns:*`
- `iam:CreateRole`
- `iam:AttachRolePolicy`
- `s3:CreateBucket`
- `s3:PutObject`
- `ec2:DescribeVpcs`
- `ec2:DescribeSubnets`
- `ec2:DescribeSecurityGroups`

## Step 1: Create S3 Bucket for Canary Artifacts

### 1.1 Navigate to S3 Console
1. Open the AWS Console and navigate to **S3**
2. Click **Create bucket**

### 1.2 Configure Bucket Settings
1. **Bucket name**: Enter a unique name (e.g., `my-canary-artifacts-[random-suffix]`)
2. **Region**: Select the same region where you'll deploy canaries
3. **Block Public Access**: Keep all options checked (recommended)
4. **Bucket Versioning**: Enable (recommended for artifact history)
5. **Default encryption**: Enable with Amazon S3 managed keys (SSE-S3)
6. Click **Create bucket**

### 1.3 Note Bucket Details
- Record the bucket name for later use
- Ensure the bucket is in the correct region

## Step 2: Create IAM Role for Canary Execution

### 2.1 Navigate to IAM Console
1. Open the AWS Console and navigate to **IAM**
2. Click **Roles** in the left sidebar
3. Click **Create role**

### 2.2 Configure Trust Relationship
1. **Trusted entity type**: Select **AWS service**
2. **Service or use case**: Select **Lambda** (Synthetics uses Lambda runtime)
3. Click **Next**

### 2.3 Attach Policies
Attach the following AWS managed policies:
1. Search and select **CloudWatchSyntheticsExecutionRolePolicy**
2. Search and select **VPCAccessExecutionsRole** (if using VPC)
3. Click **Next**

### 2.4 Configure Role Details
1. **Role name**: `CloudWatchSyntheticsRole-[environment]`
2. **Description**: `Execution role for CloudWatch Synthetics canaries`
3. Click **Create role**

### 2.5 Update Trust Policy
1. Click on the newly created role
2. Go to **Trust relationships** tab
3. Click **Edit trust policy**
4. Replace the trust policy with:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "synthetics.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```
5. Click **Update policy**

## Step 3: Configure VPC and Security Groups

### 3.1 Identify VPC Configuration
1. Navigate to **VPC** console
2. Note your VPC ID that has connectivity to on-premises
3. Identify subnets with routes to on-premises networks
4. Record subnet IDs for canary deployment

### 3.2 Create Security Group for Canaries
1. In VPC console, click **Security Groups**
2. Click **Create security group**
3. **Name**: `canary-security-group`
4. **Description**: `Security group for CloudWatch Synthetics canaries`
5. **VPC**: Select your VPC

### 3.3 Configure Security Group Rules

#### Outbound Rules (Required)
1. **Type**: All Traffic
2. **Protocol**: All
3. **Port Range**: All
4. **Destination**: Your on-premises CIDR (e.g., `10.0.0.0/8`)
5. **Description**: `Access to on-premises infrastructure`

Add additional outbound rules:
1. **Type**: HTTPS
2. **Protocol**: TCP
3. **Port Range**: 443
4. **Destination**: 0.0.0.0/0
5. **Description**: `AWS API access`

#### Inbound Rules
- No inbound rules required for canaries
- Keep default (no inbound rules)

6. Click **Create security group**
7. Record the security group ID

## Step 4: Create CloudWatch Synthetics Canary

### 4.1 Navigate to CloudWatch Synthetics
1. Open AWS Console and navigate to **CloudWatch**
2. In the left sidebar, under **Synthetics**, click **Canaries**
3. Click **Create canary**

### 4.2 Configure Canary Basics
1. **Name**: `heartbeat-canary-[environment]`
2. **Description**: `Heartbeat monitoring for on-premises infrastructure`

### 4.3 Select Blueprint
1. **Use a blueprint**: Select **Heartbeat monitoring**
2. **Application or endpoint URL**: Enter your on-premises endpoint
   - For basic connectivity: `http://[on-premises-ip]`
   - For specific service: `http://[on-premises-ip]:[port]/[path]`

### 4.4 Configure Script
1. **Runtime version**: Select latest Node.js version (e.g., `syn-nodejs-puppeteer-6.2`)
2. **Handler**: Keep default `pageLoadBlueprint.handler`

### 4.5 Configure Schedule
1. **Run continuously**: Select this option
2. **Frequency**: Choose appropriate interval
   - For critical systems: Every 1 minute
   - For standard monitoring: Every 5 minutes
   - For cost optimization: Every 15 minutes
3. **Data retention**: 31 days (default)

### 4.6 Configure Data Storage
1. **S3 bucket**: Select the bucket created in Step 1
2. **S3 bucket prefix**: `canary-artifacts/`

### 4.7 Configure Access Permissions
1. **Execution role**: Select **Use an existing role**
2. **Existing role**: Select the role created in Step 2

### 4.8 Configure VPC (Critical for On-Premises Access)
1. **VPC**: Select your VPC
2. **Subnets**: Select subnets with on-premises connectivity
3. **Security groups**: Select the security group created in Step 3

### 4.9 Configure Environment Variables (Optional)
Add environment variables for canary customization:
- `TIMEOUT`: `30000` (30 seconds)
- `RETRIES`: `3`
- `TARGET_ENDPOINT`: Your specific endpoint

### 4.10 Review and Create
1. Review all configurations
2. Click **Create canary**
3. Wait for canary to be created and start running

## Step 5: Create API Canary (Optional)

### 5.1 Create Second Canary
1. Click **Create canary** again
2. **Name**: `api-canary-[environment]`
3. **Description**: `API endpoint monitoring for on-premises services`

### 5.2 Configure API Canary
1. **Use a blueprint**: Select **API canary**
2. **Application or endpoint URL**: `http://[on-premises-ip]:[port]/api/health`
3. **HTTP method**: GET
4. **Request headers**: Add any required headers
5. **Request body**: Leave empty for GET requests

### 5.3 Configure Advanced Settings
1. Follow steps 4.4-4.10 from the heartbeat canary
2. Adjust environment variables for API testing:
   - `EXPECTED_STATUS`: `200`
   - `REQUEST_TIMEOUT`: `10000`

## Step 6: Create SNS Topic for Notifications

### 6.1 Navigate to SNS Console
1. Open AWS Console and navigate to **Simple Notification Service (SNS)**
2. Click **Topics** in the left sidebar
3. Click **Create topic**

### 6.2 Configure Topic
1. **Type**: Standard
2. **Name**: `canary-alerts-[environment]`
3. **Display name**: `Canary Monitoring Alerts`
4. Click **Create topic**

### 6.3 Create Email Subscription
1. Click on the newly created topic
2. Click **Create subscription**
3. **Protocol**: Email
4. **Endpoint**: Enter your email address
5. Click **Create subscription**
6. Check your email and confirm the subscription

### 6.4 Record Topic ARN
- Copy the Topic ARN for use in alarm configuration

## Step 7: Create CloudWatch Alarms

### 7.1 Navigate to CloudWatch Alarms
1. In CloudWatch console, click **Alarms** in the left sidebar
2. Click **Create alarm**

### 7.2 Configure Metric for Heartbeat Canary
1. Click **Select metric**
2. Navigate to **CloudWatchSynthetics** > **Canary Name**
3. Select your heartbeat canary
4. Choose metric **SuccessPercent**
5. Click **Select metric**

### 7.3 Configure Alarm Conditions
1. **Statistic**: Average
2. **Period**: 5 minutes
3. **Threshold type**: Static
4. **Whenever SuccessPercent is**: Lower than threshold
5. **Threshold value**: `100` (triggers on any failure)

### 7.4 Configure Alarm Actions
1. **Alarm state trigger**: In alarm
2. **Send a notification to**: Select the SNS topic created in Step 6
3. **Auto Scaling action**: None
4. **EC2 action**: None

### 7.5 Configure Alarm Details
1. **Alarm name**: `heartbeat-canary-failure-[environment]`
2. **Alarm description**: `Alert when heartbeat canary fails`
3. Click **Create alarm**

### 7.6 Create Additional Alarms
Repeat steps 7.1-7.5 for:
1. **Duration alarm**: Alert on high response times
   - Metric: **Duration**
   - Threshold: Greater than 30000 (30 seconds)
2. **API canary alarm**: If you created an API canary
   - Follow same process for API canary metrics

## Step 8: Verify Deployment

### 8.1 Check Canary Status
1. Navigate to **CloudWatch** > **Synthetics** > **Canaries**
2. Verify canaries show **Running** status
3. Check **Success rate** shows recent successful runs

### 8.2 Review Canary Logs
1. Click on a canary name
2. Go to **Monitoring** tab
3. Click **View logs in CloudWatch**
4. Review execution logs for any errors

### 8.3 Test Network Connectivity
1. In canary details, check **Screenshots** tab
2. Review any error messages
3. If failures occur, verify:
   - VPC routing to on-premises
   - Security group rules
   - On-premises endpoint accessibility

### 8.4 Test Alarm Notifications
1. Temporarily modify canary endpoint to invalid URL
2. Wait for canary to fail
3. Verify alarm triggers and email notification received
4. Restore correct endpoint URL

## Step 9: Configure CloudWatch Dashboard (Optional)

### 9.1 Create Dashboard
1. Navigate to **CloudWatch** > **Dashboards**
2. Click **Create dashboard**
3. **Dashboard name**: `Canary-Monitoring-[environment]`

### 9.2 Add Widgets
1. Click **Add widget**
2. **Widget type**: Line graph
3. **Metrics**: Add canary SuccessPercent and Duration metrics
4. **Period**: 5 minutes
5. Click **Create widget**

### 9.3 Add Additional Widgets
Consider adding:
- Number widgets for current success rate
- Log insights widget for error analysis
- Alarm status widget

## Troubleshooting Common Issues

### Canary Creation Fails
- **Issue**: Permission denied
- **Solution**: Verify IAM role has correct policies and trust relationship

### Canary Runs but Always Fails
- **Issue**: Network connectivity
- **Solution**: 
  1. Check VPC routing tables
  2. Verify security group outbound rules
  3. Test VPN/Direct Connect connectivity
  4. Confirm on-premises endpoint is accessible

### No Alarm Notifications
- **Issue**: SNS subscription not confirmed
- **Solution**: Check email and confirm SNS subscription

### High Costs
- **Issue**: Frequent canary execution
- **Solution**: 
  1. Reduce canary frequency
  2. Review data retention settings
  3. Consider consolidating multiple endpoints into single canary

## Cost Optimization Tips

1. **Execution Frequency**: Balance monitoring needs with cost
   - Critical systems: 1-5 minutes
   - Standard systems: 5-15 minutes
   - Development: 30+ minutes

2. **Data Retention**: Reduce retention period if not needed
   - Production: 31 days
   - Development: 7 days

3. **Artifact Storage**: Regularly clean up old S3 artifacts

4. **Multiple Endpoints**: Use single canary to test multiple endpoints when possible

## Security Best Practices

1. **IAM Roles**: Use least-privilege access
2. **VPC Configuration**: Restrict security group rules to necessary traffic
3. **Encryption**: Enable S3 bucket encryption for artifacts
4. **Network Isolation**: Use private subnets for canary execution
5. **Monitoring**: Enable CloudTrail for API call auditing

## Next Steps

After successful manual deployment:

1. **Monitor Performance**: Review canary metrics and adjust thresholds
2. **Automate Deployment**: Consider using CloudFormation/CDK for future deployments
3. **Expand Monitoring**: Add more canaries for additional endpoints
4. **Integrate with CI/CD**: Include canary deployment in your deployment pipeline
5. **Cost Monitoring**: Set up billing alerts for Synthetics usage

## Support and Resources

- **AWS Documentation**: [CloudWatch Synthetics User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Canaries.html)
- **Troubleshooting**: Review CloudWatch Synthetics logs and metrics
- **Community**: AWS forums and Stack Overflow
- **Professional Support**: AWS Support plans for production workloads

---

This manual deployment guide provides a comprehensive approach to setting up CloudWatch Synthetics monitoring using the AWS Console. For automated deployments, refer to the [Deployment Guide](deployment-guide.md).