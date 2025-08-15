# Documentation

This directory contains comprehensive documentation for the CloudWatch Synthetics monitoring solution.

## Deployment Guides

### Automated Deployment
- [`deployment-guide.md`](deployment-guide.md) - Automated deployment using CloudFormation/CDK
- [`alarm-notification-guide.md`](alarm-notification-guide.md) - CloudWatch alarms and SNS notification setup

### Manual Deployment
- [`manual-deployment-guide.md`](manual-deployment-guide.md) - Complete manual deployment using AWS Console
- [`vpc-configuration-guide.md`](vpc-configuration-guide.md) - Detailed VPC and networking configuration
- [`manual-deployment-checklist.md`](manual-deployment-checklist.md) - Quick reference checklist

## Operational Guides

- [`error-handling-guide.md`](error-handling-guide.md) - Error handling and troubleshooting
- `network-setup.md` - VPC and VPN configuration requirements *(planned)*
- `cost-optimization.md` - Cost analysis and monitoring frequency recommendations *(planned)*
- `troubleshooting.md` - Common issues and resolution steps *(planned)*

## Guide Selection

### Choose Manual Deployment When:
- Learning CloudWatch Synthetics concepts
- Setting up proof-of-concept or testing
- Need fine-grained control over configuration
- Working in environments without automation tools
- Troubleshooting existing deployments

### Choose Automated Deployment When:
- Deploying to production environments
- Need repeatable, consistent deployments
- Managing multiple environments
- Integrating with CI/CD pipelines
- Following infrastructure-as-code practices

## Best Practices

- Security considerations for network architecture
- Canary configuration recommendations
- Monitoring and alerting best practices
- Cost optimization strategies
- Network connectivity requirements