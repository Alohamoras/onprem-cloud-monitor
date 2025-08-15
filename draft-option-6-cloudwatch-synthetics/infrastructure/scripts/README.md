# Deployment Automation Scripts

This directory contains comprehensive deployment automation scripts for the CloudWatch Synthetics Canary monitoring solution. These scripts provide parameter validation, pre-deployment checks, deployment execution, status monitoring, rollback capabilities, and cleanup functionality.

## Scripts Overview

### Main Deployment Script

- **`deploy.sh`** - Main orchestrator script that coordinates the entire deployment process

### Core Automation Scripts

- **`deploy-automation.sh`** - Comprehensive deployment automation with validation and monitoring
- **`validate-parameters.sh`** - Parameter validation and configuration verification
- **`monitor-deployment.sh`** - Real-time deployment status monitoring
- **`rollback.sh`** - Rollback capabilities for failed deployments
- **`cleanup.sh`** - Resource cleanup and maintenance

## Quick Start

### Basic Deployment

```bash
# Deploy to development environment
./scripts/deploy.sh --environment dev --config ./config/dev.json

# Deploy to production with CDK
./scripts/deploy.sh --type cdk --environment prod --config ./config/prod.json
```

### Dry Run

```bash
# Test deployment without making changes
./scripts/deploy.sh --dry-run --config ./config/staging.json
```

## Configuration File Format

Create a JSON configuration file with your deployment parameters:

```json
{
    "vpcId": "vpc-12345678",
    "subnetIds": ["subnet-12345678", "subnet-87654321"],
    "notificationEmail": "admin@example.com",
    "targetEndpoint": "192.168.1.100",
    "targetPort": 8080,
    "onPremisesCIDR": "192.168.0.0/16",
    "monitoringFrequency": "rate(5 minutes)",
    "canaryName": "production-monitor",
    "alarmThreshold": 2,
    "escalationThreshold": 5,
    "highLatencyThreshold": 5000,
    "artifactRetentionDays": 30,
    "escalationEmail": "escalation@example.com",
    "slackWebhookUrl": "https://hooks.slack.com/services/..."
}
```

## Detailed Script Usage

### 1. Main Deployment Orchestrator (`deploy.sh`)

The main script that coordinates the entire deployment process.

```bash
./scripts/deploy.sh [OPTIONS]

Options:
  -t, --type TYPE             Deployment type (cloudformation|cdk) [default: cloudformation]
  -e, --environment ENV       Environment name (dev, staging, prod) [default: dev]
  -r, --region REGION         AWS region [default: us-east-1]
  -s, --stack-name NAME       Custom stack name (auto-generated if not provided)
  -p, --profile PROFILE       AWS profile to use
  -c, --config FILE           Configuration file with deployment parameters
  --skip-validation           Skip pre-deployment parameter validation
  --skip-backup               Skip backup of existing resources
  --skip-monitoring           Skip deployment status monitoring
  --no-rollback               Disable automatic rollback on failure
  --cleanup-on-failure        Clean up resources if deployment fails
  --dry-run                   Perform validation and show what would be deployed
  -f, --force                 Force deployment even if validation warnings exist
  -v, --verbose               Enable verbose output
  -h, --help                  Show this help message
```

**Examples:**
```bash
# Standard deployment
./scripts/deploy.sh --environment prod --config ./config/prod.json

# Deployment with custom options
./scripts/deploy.sh --type cdk --environment staging --config ./config/staging.json --verbose

# Force deployment despite warnings
./scripts/deploy.sh --environment dev --config ./config/dev.json --force

# Deployment with cleanup on failure
./scripts/deploy.sh --environment prod --config ./config/prod.json --cleanup-on-failure
```

### 2. Parameter Validation (`validate-parameters.sh`)

Validates deployment parameters and AWS resources before deployment.

```bash
./scripts/validate-parameters.sh [OPTIONS]

Options:
  -c, --config FILE           Configuration file to validate (required)
  -r, --region REGION         AWS region [default: us-east-1]
  -p, --profile PROFILE       AWS profile to use
  -t, --type TYPE             Validation type (all|network|aws-resources|configuration) [default: all]
  -s, --strict                Enable strict validation mode (warnings become errors)
  -o, --output FORMAT         Output format (text|json) [default: text]
  -v, --verbose               Enable verbose output
```

**Examples:**
```bash
# Validate all parameters
./scripts/validate-parameters.sh --config ./config/prod.json

# Validate only network configuration
./scripts/validate-parameters.sh --config ./config/dev.json --type network

# Strict validation with JSON output
./scripts/validate-parameters.sh --config ./config/prod.json --strict --output json
```

### 3. Deployment Monitoring (`monitor-deployment.sh`)

Monitors deployment status and provides real-time updates.

```bash
./scripts/monitor-deployment.sh [OPTIONS]

Options:
  -s, --stack-name NAME       Stack name to monitor (required)
  -r, --region REGION         AWS region [default: us-east-1]
  -p, --profile PROFILE       AWS profile to use
  -t, --type TYPE             Monitor type (deployment|health|both) [default: deployment]
  --timeout SECONDS           Monitoring timeout in seconds [default: 3600]
  --interval SECONDS          Check interval in seconds [default: 30]
  --continuous                Continue monitoring after deployment completes
  --alert-email EMAIL         Send email alerts on status changes
  --webhook-url URL           Send webhook notifications on status changes
  -v, --verbose               Enable verbose output
```

**Examples:**
```bash
# Monitor deployment status
./scripts/monitor-deployment.sh --stack-name my-canary-stack --type deployment

# Monitor health status continuously
./scripts/monitor-deployment.sh --stack-name my-canary-stack --type health --continuous

# Monitor with email alerts
./scripts/monitor-deployment.sh --stack-name my-canary-stack --alert-email admin@example.com
```

### 4. Rollback (`rollback.sh`)

Provides rollback capabilities for failed deployments.

```bash
./scripts/rollback.sh [OPTIONS]

Options:
  -s, --stack-name NAME       Stack name to rollback (required)
  -r, --region REGION         AWS region [default: us-east-1]
  -p, --profile PROFILE       AWS profile to use
  -b, --backup-file FILE      Specific backup file to restore from
  -t, --type TYPE             Rollback type (delete|restore|previous-version) [default: delete]
  -f, --force                 Force rollback without confirmation
  -v, --verbose               Enable verbose output
```

**Examples:**
```bash
# Delete a failed stack
./scripts/rollback.sh --stack-name my-canary-stack --type delete

# Restore from a specific backup
./scripts/rollback.sh --stack-name my-canary-stack --type restore --backup-file ./backups/stack-backup.json

# Rollback to previous version
./scripts/rollback.sh --stack-name my-canary-stack --type previous-version
```

### 5. Cleanup (`cleanup.sh`)

Cleans up deployment resources and artifacts.

```bash
./scripts/cleanup.sh [OPTIONS]

Options:
  -s, --stack-name NAME       Stack name to cleanup (required for stack cleanup)
  -r, --region REGION         AWS region [default: us-east-1]
  -p, --profile PROFILE       AWS profile to use
  -t, --type TYPE             Cleanup type (all|stack-only|artifacts-only|logs-only) [default: all]
  --retention-days DAYS       Keep artifacts/logs newer than N days [default: 30]
  --dry-run                   Show what would be cleaned up without doing it
  -f, --force                 Force cleanup without confirmation
  -v, --verbose               Enable verbose output
```

**Examples:**
```bash
# Clean up everything for a specific stack
./scripts/cleanup.sh --stack-name my-canary-stack --type all

# Clean up only artifacts older than 7 days
./scripts/cleanup.sh --type artifacts-only --retention-days 7

# Dry run to see what would be cleaned up
./scripts/cleanup.sh --stack-name my-canary-stack --dry-run
```

## Deployment Workflow

The deployment automation follows this workflow:

1. **Parameter Validation** - Validates configuration parameters and AWS resources
2. **Pre-deployment Checks** - Verifies prerequisites and permissions
3. **Resource Backup** - Creates backups of existing resources
4. **Deployment Execution** - Deploys using CloudFormation or CDK
5. **Status Monitoring** - Monitors deployment progress in real-time
6. **Rollback on Failure** - Automatically rolls back if deployment fails
7. **Cleanup on Failure** - Optionally cleans up resources after failure

## Prerequisites

### Required Tools

- **AWS CLI** - For AWS resource management
- **jq** - For JSON processing
- **Node.js & npm** - For CDK deployments
- **AWS CDK** - For CDK deployments (`npm install -g aws-cdk`)

### AWS Permissions

The scripts require the following AWS permissions:

- **CloudFormation**: Full access for stack management
- **CloudWatch Synthetics**: Full access for canary management
- **S3**: Access for artifact storage
- **CloudWatch**: Access for metrics and alarms
- **SNS**: Access for notifications
- **EC2**: Read access for VPC/subnet validation
- **IAM**: Access for role creation and management

### Installation

```bash
# Install AWS CLI (if not already installed)
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Install jq (if not already installed)
brew install jq  # macOS
# or
sudo apt-get install jq  # Ubuntu/Debian

# Install Node.js and CDK (for CDK deployments)
brew install node  # macOS
npm install -g aws-cdk
```

## Configuration Examples

### Development Environment

```json
{
    "vpcId": "vpc-dev123456",
    "subnetIds": ["subnet-dev123456"],
    "notificationEmail": "dev-team@example.com",
    "targetEndpoint": "192.168.1.100",
    "targetPort": 8080,
    "onPremisesCIDR": "192.168.0.0/16",
    "monitoringFrequency": "rate(10 minutes)",
    "canaryName": "dev-monitor",
    "alarmThreshold": 3,
    "artifactRetentionDays": 7
}
```

### Production Environment

```json
{
    "vpcId": "vpc-prod123456",
    "subnetIds": ["subnet-prod123456", "subnet-prod789012"],
    "notificationEmail": "ops-team@example.com",
    "targetEndpoint": "10.0.1.100",
    "targetPort": 8080,
    "onPremisesCIDR": "10.0.0.0/8",
    "monitoringFrequency": "rate(5 minutes)",
    "canaryName": "prod-monitor",
    "alarmThreshold": 2,
    "escalationThreshold": 5,
    "highLatencyThreshold": 3000,
    "artifactRetentionDays": 90,
    "escalationEmail": "escalation@example.com",
    "slackWebhookUrl": "https://hooks.slack.com/services/..."
}
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure AWS credentials are configured: `aws configure`
   - Verify IAM permissions for required services

2. **VPC/Subnet Not Found**
   - Check VPC ID and subnet IDs in configuration
   - Ensure resources exist in the specified region

3. **Deployment Timeout**
   - Increase timeout values in monitoring scripts
   - Check CloudFormation events for detailed error information

4. **Rollback Failures**
   - Check for resources that prevent deletion
   - Use cleanup script to remove orphaned resources

### Debug Mode

Enable verbose output for detailed logging:

```bash
./scripts/deploy.sh --verbose --config ./config/dev.json
```

### Log Files

All scripts generate log files in the `logs/` directory:

- `deployment-YYYYMMDD-HHMMSS.log` - Deployment logs
- `validation-YYYYMMDD-HHMMSS.log` - Validation logs
- `monitor-YYYYMMDD-HHMMSS.log` - Monitoring logs
- `rollback-YYYYMMDD-HHMMSS.log` - Rollback logs
- `cleanup-YYYYMMDD-HHMMSS.log` - Cleanup logs

## Best Practices

1. **Always validate parameters** before deployment
2. **Use dry-run mode** to test deployments
3. **Enable monitoring** for production deployments
4. **Keep backups** of working configurations
5. **Use environment-specific configurations**
6. **Monitor deployment logs** for issues
7. **Test rollback procedures** in non-production environments
8. **Clean up old resources** regularly to manage costs

## Support

For issues or questions:

1. Check the log files for detailed error information
2. Review the troubleshooting section above
3. Verify AWS permissions and resource availability
4. Test with dry-run mode to identify configuration issues