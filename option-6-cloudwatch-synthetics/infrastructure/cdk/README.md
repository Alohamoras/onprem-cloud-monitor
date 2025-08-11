# CloudWatch Synthetics CDK Implementation

This directory contains the AWS CDK (Cloud Development Kit) implementation for deploying CloudWatch Synthetics canaries to monitor on-premises infrastructure. This provides a type-safe, infrastructure-as-code alternative to CloudFormation templates.

## Features

- **Reusable CDK Constructs**: Modular constructs for canary creation and alarm configuration
- **Type-Safe Interfaces**: Comprehensive TypeScript interfaces for configuration
- **Automated Deployment**: Scripts for easy deployment and management
- **Multiple Environments**: Support for dev, staging, and production configurations
- **Comprehensive Monitoring**: Heartbeat and API canaries with full alarm coverage
- **Cost Optimization**: Built-in cost tracking and optimization recommendations

## Architecture

### Core Components

1. **CanaryConstruct**: Reusable construct for creating CloudWatch Synthetics canaries
2. **AlarmConstruct**: Reusable construct for creating comprehensive alarm coverage
3. **CanaryInfrastructureStack**: Main stack that orchestrates all resources
4. **Type-Safe Interfaces**: Comprehensive interfaces for configuration and monitoring

### Directory Structure

```
cdk/
├── bin/                    # CDK app entry point
│   └── app.ts
├── lib/                    # CDK constructs and stacks
│   ├── constructs/         # Reusable constructs
│   │   ├── canary-construct.ts
│   │   └── alarm-construct.ts
│   ├── interfaces/         # Type definitions
│   │   └── monitoring-interfaces.ts
│   └── canary-infrastructure-stack.ts
├── examples/               # Configuration examples
│   ├── dev-config.json
│   ├── staging-config.json
│   └── prod-config.json
├── scripts/                # Deployment scripts
│   └── deploy.sh
├── package.json
├── cdk.json
├── tsconfig.json
└── README.md
```

## Quick Start

### Prerequisites

1. **Node.js**: Version 18.x or later
2. **AWS CDK**: Install globally with `npm install -g aws-cdk`
3. **AWS CLI**: Configured with appropriate credentials
4. **jq**: For JSON processing in deployment scripts

### Installation

1. Navigate to the CDK directory:
   ```bash
   cd option-6-cloudwatch-synthetics/infrastructure/cdk
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Build the project:
   ```bash
   npm run build
   ```

### Configuration

Create a configuration file based on the examples in the `examples/` directory:

```bash
cp examples/dev-config.json my-config.json
```

Edit the configuration file with your specific values:

```json
{
  "canaryName": "my-onprem-monitor",
  "monitoringFrequency": "rate(5 minutes)",
  "vpcId": "vpc-12345678",
  "subnetIds": ["subnet-12345678", "subnet-87654321"],
  "onPremisesCIDR": "10.0.0.0/8",
  "targetEndpoint": "10.1.1.100",
  "targetPort": 80,
  "notificationEmail": "alerts@company.com"
}
```

### Deployment

#### Using the Deployment Script (Recommended)

```bash
# Deploy to dev environment
./scripts/deploy.sh --environment dev --context my-config.json

# Deploy to production
./scripts/deploy.sh --environment prod --context examples/prod-config.json

# Show deployment diff
./scripts/deploy.sh --diff --context my-config.json

# Destroy stack
./scripts/deploy.sh --destroy --environment dev
```

#### Using CDK Commands Directly

```bash
# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy with context
cdk deploy --context canaryName=my-monitor \
           --context vpcId=vpc-12345678 \
           --context subnetIds=subnet-12345678,subnet-87654321 \
           --context notificationEmail=alerts@company.com \
           --context targetEndpoint=10.1.1.100

# Show diff
cdk diff

# Destroy
cdk destroy
```

## Configuration Reference

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `vpcId` | VPC ID where canaries will run | `vpc-12345678` |
| `subnetIds` | Comma-separated subnet IDs | `subnet-12345678,subnet-87654321` |
| `notificationEmail` | Email for alarm notifications | `alerts@company.com` |
| `targetEndpoint` | On-premises endpoint to monitor | `10.1.1.100` |

### Optional Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `canaryName` | Name prefix for canaries | `on-premises-monitor` |
| `monitoringFrequency` | Canary execution frequency | `rate(5 minutes)` |
| `onPremisesCIDR` | On-premises network CIDR | `10.0.0.0/8` |
| `targetPort` | Target port to monitor | `80` |
| `alarmThreshold` | Failure count for alarms | `2` |
| `escalationThreshold` | Failure count for escalation | `5` |
| `highLatencyThreshold` | Latency threshold (ms) | `5000` |
| `enableEscalation` | Enable escalation alarms | `true` |
| `artifactRetentionDays` | Artifact retention period | `30` |

### Advanced Configuration

#### Additional Monitoring Targets

You can specify additional monitoring targets in your configuration:

```json
{
  "additionalTargets": [
    {
      "name": "api-health-check",
      "type": "api",
      "endpoint": "http://10.1.1.100:8080/health",
      "timeout": 10000,
      "retries": 3,
      "expectedStatusCodes": [200],
      "validateContent": true,
      "expectedContentPattern": "healthy"
    },
    {
      "name": "database-connectivity",
      "type": "heartbeat",
      "endpoint": "tcp://10.1.1.200:5432",
      "timeout": 15000,
      "retries": 2
    }
  ]
}
```

#### Notification Configuration

```json
{
  "notificationEmail": "primary@company.com",
  "escalationEmail": "oncall@company.com",
  "slackWebhookUrl": "https://hooks.slack.com/services/..."
}
```

## Constructs Reference

### CanaryConstruct

Creates a CloudWatch Synthetics canary with the specified configuration.

```typescript
import { CanaryConstruct } from './constructs/canary-construct';

const canary = new CanaryConstruct(this, 'MyCanary', {
  config: {
    name: 'my-canary',
    schedule: { expression: 'rate(5 minutes)' },
    target: {
      name: 'my-target',
      type: 'heartbeat',
      endpoint: 'http://example.com',
      timeout: 30000
    },
    // ... other configuration
  },
  executionRole: role,
  artifactsBucket: bucket,
  securityGroup: sg,
  vpc: vpc
});
```

### AlarmConstruct

Creates comprehensive CloudWatch alarms for a canary.

```typescript
import { AlarmConstruct } from './constructs/alarm-construct';

const alarms = new AlarmConstruct(this, 'MyAlarms', {
  canary: canary.canary,
  canaryType: 'heartbeat',
  alarmConfig: {
    failureThreshold: 1,
    durationThreshold: 45000,
    successRateThreshold: 80,
    highLatencyThreshold: 5000,
    evaluationPeriods: 2,
    treatMissingData: TreatMissingData.BREACHING,
    enableEscalation: true
  },
  notificationTopic: topic,
  stackName: 'MyStack'
});
```

## Monitoring Types

### Heartbeat Canary

Performs basic connectivity testing to endpoints:

- TCP/HTTP connectivity checks
- Response time measurement
- Retry logic with exponential backoff
- Custom metrics for success/failure rates

### API Canary

Performs comprehensive API endpoint testing:

- HTTP request/response validation
- Status code verification
- Content validation with regex patterns
- Custom headers support
- Redirect following
- Response size limits

## Alarms and Notifications

### Alarm Types

1. **Failure Alarm**: Triggers on canary failures
2. **Duration Alarm**: Triggers on slow canary execution
3. **Success Rate Alarm**: Triggers on low success rates
4. **High Latency Alarm**: Triggers on high response times
5. **Escalation Alarm**: Triggers on consecutive failures
6. **Composite Alarm**: Overall health status

### Notification Channels

- **Email**: SNS email notifications
- **Slack**: Webhook integration with formatted messages
- **SMS**: SNS SMS notifications (configurable)
- **PagerDuty**: Integration support (configurable)

## Cost Optimization

### Cost Factors

1. **Canary Executions**: Based on frequency and duration
2. **Data Storage**: S3 storage for artifacts
3. **CloudWatch Alarms**: Number of alarm evaluations
4. **SNS Notifications**: Email and SMS costs

### Optimization Strategies

1. **Frequency Tuning**: Balance monitoring coverage with cost
2. **Artifact Retention**: Configure appropriate retention periods
3. **Alarm Consolidation**: Use composite alarms to reduce evaluations
4. **Regional Deployment**: Deploy in cost-effective regions

### Cost Estimation

Use the built-in cost estimation interfaces:

```typescript
interface CostEstimate {
  canaryExecutions: {
    monthly: number;
    costPerExecution: number;
    totalMonthlyCost: number;
  };
  totalEstimatedMonthlyCost: number;
}
```

## Troubleshooting

### Common Issues

1. **VPC Connectivity**: Ensure proper routing and security groups
2. **IAM Permissions**: Verify canary execution role permissions
3. **DNS Resolution**: Check DNS settings in VPC
4. **Network ACLs**: Verify network ACL rules allow traffic

### Debugging

1. **CloudWatch Logs**: Check canary execution logs
2. **VPC Flow Logs**: Analyze network traffic
3. **CDK Diff**: Compare deployed vs. desired state
4. **AWS Console**: Use Synthetics console for debugging

### Log Analysis

Canary logs are available in CloudWatch Logs:
- Log Group: `/aws/lambda/cwsyn-{canary-name}-{random-id}`
- Metrics: Custom metrics in `CloudWatchSynthetics/UserAgentMetrics` namespace

## Development

### Building

```bash
npm run build
```

### Testing

```bash
npm test
```

### Linting

```bash
npm run lint
```

### Type Checking

```bash
npx tsc --noEmit
```

## Examples

See the `examples/` directory for complete configuration examples:

- `dev-config.json`: Development environment setup
- `staging-config.json`: Staging environment setup  
- `prod-config.json`: Production environment setup

## Support

For issues and questions:

1. Check the troubleshooting section
2. Review CloudWatch Logs for canary execution details
3. Verify network connectivity and permissions
4. Consult AWS CDK and CloudWatch Synthetics documentation

## License

This project is licensed under the MIT License - see the LICENSE file for details.