# CloudWatch Canary Synthetics Monitoring Solution

This directory contains the implementation of Option 6: CloudWatch Canary Synthetics for monitoring on-premises devices and endpoints.

## Directory Structure

- `canary-scripts/` - Node.js canary scripts for heartbeat and API monitoring
- `infrastructure/` - CloudFormation and CDK templates for deployment
- `docs/` - Documentation and deployment guides
- `examples/` - Example configurations and test scenarios

## Quick Start

1. Review the deployment guide in `docs/deployment-guide.md`
2. Configure your VPC and network connectivity
3. Deploy using CloudFormation templates in `infrastructure/cloudformation/`
4. Or use CDK deployment from `infrastructure/cdk/`

## Cost Considerations

See `docs/cost-optimization.md` for detailed cost analysis and monitoring frequency recommendations.