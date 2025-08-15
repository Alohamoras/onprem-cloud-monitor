# CloudWatch Synthetics Deployment Guide

This guide provides step-by-step instructions for deploying the CloudWatch Synthetics monitoring solution for on-premises infrastructure.

## Prerequisites

### AWS Requirements
- AWS CLI installed and configured
- Appropriate IAM permissions for CloudFormation/CDK deployment
- VPC with connectivity to on-premises infrastructure (VPN or Direct Connect)
- Subnets with routes to on-premises networks

### Local Requirements
- For CloudFormation: AWS CLI
- For CDK: Node.js 18+ and AWS CDK CLI

## Deployment Options

### Option 1: CloudFormation Deployment

1. **Configure Parameters**
   ```bash
   cd option-6-cloudwatch-synthetics/infrastructure
   cp cloudformation/parameters/dev-parameters.json cloudformation/parameters/my-env-parameters.json
   ```

2. **Edit Parameters**
   Update the parameter values in `my-env-parameters.json`:
   - `VpcId`: Your VPC ID
   - `SubnetIds`: Comma-separated subnet IDs with on-premises connectivity
   - `OnPremisesCIDR`: CIDR block of your on-premises network
   - `TargetEndpoint`: Primary endpoint to monitor
   - `NotificationEmail`: Email for alarm notifications

3. **Deploy Stack**
   ```bash
   ./deploy-cloudformation.sh --environment my-env --stack-name my-canary-stack
   ```

### Option 2: CDK Deployment

1. **Set Environment Variables**
   ```bash
   export VPC_ID="vpc-xxxxxxxxx"
   export SUBNET_IDS="subnet-xxxxxxxxx,subnet-yyyyyyyyy"
   export NOTIFICATION_EMAIL="your-email@example.com"
   export TARGET_ENDPOINT="10.1.1.100"
   ```

2. **Deploy with CDK**
   ```bash
   cd option-6-cloudwatch-synthetics/infrastructure
   ./deploy-cdk.sh --environment prod
   ```

## Post-Deployment Configuration

### 1. Verify Network Connectivity
- Ensure canaries can reach on-premises endpoints
- Check security group rules
- Validate VPN/Direct Connect connectivity

### 2. Test Canary Execution
- Monitor CloudWatch Synthetics console
- Check canary execution logs
- Verify metrics are being published

### 3. Configure Alarms
- Review default alarm thresholds
- Adjust notification settings
- Test alarm notifications

## Troubleshooting

### Common Issues
1. **Network Connectivity**: Check VPC routes and security groups
2. **Permission Errors**: Verify IAM roles and policies
3. **Canary Failures**: Review execution logs in CloudWatch

### Validation Steps
1. Check canary status in AWS Console
2. Verify CloudWatch metrics
3. Test alarm notifications
4. Review S3 artifacts

## Next Steps

After successful deployment:
1. Implement canary scripts (Task 2)
2. Configure specific monitoring targets
3. Set up custom dashboards
4. Implement cost optimization strategies

## Support

For issues or questions:
1. Check troubleshooting documentation
2. Review CloudWatch Synthetics logs
3. Validate network connectivity
4. Contact your AWS support team