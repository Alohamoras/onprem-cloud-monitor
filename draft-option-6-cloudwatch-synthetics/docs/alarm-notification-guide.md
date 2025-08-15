# CloudWatch Synthetics Alarm and Notification System

## Overview

This guide covers the comprehensive CloudWatch alarm and notification system implemented for CloudWatch Synthetics canaries. The system provides multi-layered monitoring with configurable thresholds, escalation logic, and multiple notification channels.

## Architecture

### Alarm Types

The system implements several types of alarms for comprehensive monitoring:

#### 1. Failure Alarms
- **Purpose**: Detect when canaries fail to execute successfully
- **Metric**: `CloudWatchSynthetics.Failed`
- **Threshold**: Configurable (default: 1 failure)
- **Evaluation Periods**: Configurable (default: 2)
- **Treatment**: Missing data treated as breaching

#### 2. Escalation Alarms
- **Purpose**: Trigger escalated notifications for multiple consecutive failures
- **Metric**: `CloudWatchSynthetics.Failed`
- **Threshold**: 1 failure
- **Evaluation Periods**: Configurable escalation threshold (default: 5)
- **Treatment**: Missing data treated as breaching

#### 3. Duration Alarms
- **Purpose**: Detect when canary execution takes too long
- **Metric**: `CloudWatchSynthetics.Duration`
- **Threshold**: 45,000ms (45 seconds)
- **Evaluation Periods**: 3
- **Treatment**: Missing data treated as not breaching

#### 4. Success Rate Alarms
- **Purpose**: Monitor overall success percentage over time
- **Metric**: `CloudWatchSynthetics.SuccessPercent`
- **Threshold**: 80%
- **Evaluation Periods**: 2
- **Period**: 15 minutes
- **Treatment**: Missing data treated as not breaching

#### 5. High Latency Alarms
- **Purpose**: Detect when response times exceed acceptable thresholds
- **Metric**: `CloudWatchSynthetics/UserAgentMetrics.ResponseTime` or `ApiResponseTime`
- **Threshold**: Configurable (default: 5000ms)
- **Evaluation Periods**: 2
- **Treatment**: Missing data treated as not breaching

#### 6. Composite Alarm
- **Purpose**: Provide overall health status across all critical alarms
- **Rule**: OR condition across failure and duration alarms
- **Actions**: Same notification channels as individual alarms

## Notification Channels

### 1. Email Notifications

#### Primary Email
- **Purpose**: Standard alarm notifications
- **Configuration**: Required parameter `NotificationEmail`
- **Triggers**: All alarm state changes (ALARM, OK)

#### Escalation Email
- **Purpose**: Escalated notifications for severe issues
- **Configuration**: Optional parameter `EscalationEmail`
- **Triggers**: Escalation alarms only
- **Condition**: Only active when `EnableEscalation=true`

### 2. Slack Notifications

#### Configuration
- **Parameter**: `SlackWebhookUrl`
- **Implementation**: Lambda function with Python runtime
- **Features**:
  - Color-coded messages based on alarm state
  - Structured message format with alarm details
  - Automatic retry logic

#### Message Format
```json
{
  "attachments": [
    {
      "color": "#FF0000",  // Red for ALARM, Green for OK
      "title": "CloudWatch Alarm: alarm-name",
      "fields": [
        {
          "title": "State",
          "value": "ALARM",
          "short": true
        },
        {
          "title": "Timestamp",
          "value": "2024-01-01T12:00:00Z",
          "short": true
        },
        {
          "title": "Reason",
          "value": "Threshold Crossed: 1 out of the last 2 datapoints...",
          "short": false
        }
      ]
    }
  ]
}
```

## Escalation Logic

### Configuration Parameters

- **AlarmThreshold**: Number of consecutive failures before initial alarm (default: 2)
- **EscalationThreshold**: Number of consecutive failures before escalation (default: 5)
- **EnableEscalation**: Boolean flag to enable/disable escalation (default: true)

### Escalation Flow

1. **Initial Failure**: Canary fails once - no alarm triggered
2. **Alarm Threshold**: After N consecutive failures - primary alarm triggers
3. **Escalation Threshold**: After M consecutive failures - escalation alarm triggers
4. **Recovery**: When canary succeeds - all alarms return to OK state

### Example Escalation Timeline

```
Time    Canary State    Primary Alarm    Escalation Alarm    Notifications
00:00   SUCCESS         OK               OK                  -
00:05   FAILED          OK               OK                  -
00:10   FAILED          ALARM            OK                  Email sent
00:15   FAILED          ALARM            OK                  -
00:20   FAILED          ALARM            OK                  -
00:25   FAILED          ALARM            ALARM               Escalation email sent
00:30   SUCCESS         OK               OK                  Recovery emails sent
```

## Cost Optimization

### Alarm Evaluation Costs

- **Standard Alarms**: $0.10 per 1,000 alarm evaluations
- **Composite Alarms**: $0.50 per 1,000 alarm evaluations
- **Evaluation Frequency**: Based on canary execution frequency

### Cost Estimation Formula

```
Monthly Alarm Cost = (Number of Alarms × Executions per Month × $0.10) / 1000
```

### Example Cost Calculation

For a setup with:
- 2 canaries
- 6 alarms per canary (12 total alarms)
- 1 composite alarm
- 5-minute execution frequency (8,640 executions/month)

```
Standard Alarms: (12 × 8,640 × $0.10) / 1000 = $10.37
Composite Alarm: (1 × 8,640 × $0.50) / 1000 = $4.32
Total Monthly Cost: $14.69
```

### Cost Optimization Strategies

1. **Adjust Evaluation Periods**: Increase evaluation periods to reduce false positives
2. **Optimize Frequency**: Use longer periods for non-critical environments
3. **Selective Alarming**: Disable non-essential alarms in development environments
4. **Composite Alarms**: Use composite alarms to reduce notification noise

## Configuration Examples

### Development Environment
```json
{
  "AlarmThreshold": 3,
  "EscalationThreshold": 10,
  "HighLatencyThreshold": 8000,
  "EnableEscalation": true,
  "MonitoringFrequency": "rate(15 minutes)"
}
```

### Production Environment
```json
{
  "AlarmThreshold": 2,
  "EscalationThreshold": 5,
  "HighLatencyThreshold": 5000,
  "EnableEscalation": true,
  "MonitoringFrequency": "rate(5 minutes)"
}
```

## Deployment

### CloudFormation Deployment

```bash
# Deploy with enhanced alarm configuration
aws cloudformation deploy \
  --template-file main-template.yaml \
  --stack-name synthetics-monitoring \
  --parameter-overrides file://prod-parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

### CDK Deployment

```typescript
const config: CanaryConfig = {
  canaryName: 'prod-monitor',
  alarmThreshold: 2,
  escalationThreshold: 5,
  enableEscalation: true,
  notificationEmail: 'ops@example.com',
  escalationEmail: 'manager@example.com',
  slackWebhookUrl: 'https://hooks.slack.com/...'
};

const stack = new CanaryInfrastructureStack(app, 'SyntheticsStack', { config });
```

## Management and Testing

### Alarm Manager Utility

The `alarm-manager.py` script provides comprehensive alarm management:

```bash
# Validate configuration
python3 alarm-manager.py validate

# Create all alarms
python3 alarm-manager.py create-all \
  --canaries heartbeat-canary api-canary \
  --notification-topic arn:aws:sns:us-east-1:123456789012:alarms

# Estimate costs
python3 alarm-manager.py estimate-costs \
  --canary-count 2 \
  --frequency "rate(5 minutes)"
```

### Alarm Testing

The `test-alarms.py` script provides testing capabilities:

```bash
# Test failure simulation
python3 test-alarms.py simulate-failure \
  --canary-name my-canary \
  --duration 10

# Test high latency alarm
python3 test-alarms.py test-latency \
  --canary-name my-canary \
  --latency 10000

# Monitor alarm states
python3 test-alarms.py monitor \
  --alarm-names alarm1 alarm2 \
  --duration 15 \
  --output test-report.txt
```

## Troubleshooting

### Common Issues

#### 1. Alarms Not Triggering
- **Check Metric Data**: Verify canary is publishing metrics
- **Review Thresholds**: Ensure thresholds are appropriate
- **Validate Dimensions**: Confirm alarm dimensions match metric dimensions

#### 2. False Positive Alarms
- **Increase Evaluation Periods**: Reduce sensitivity to transient issues
- **Adjust Thresholds**: Set more appropriate threshold values
- **Review Missing Data Treatment**: Ensure proper handling of missing data

#### 3. Notification Issues
- **SNS Topic Permissions**: Verify CloudWatch can publish to SNS
- **Email Subscriptions**: Confirm email subscriptions are confirmed
- **Slack Webhook**: Test webhook URL and Lambda function logs

### Debugging Commands

```bash
# Check alarm state
aws cloudwatch describe-alarms --alarm-names my-alarm

# View alarm history
aws cloudwatch describe-alarm-history --alarm-name my-alarm

# Test SNS topic
aws sns publish --topic-arn arn:aws:sns:us-east-1:123456789012:alarms \
  --message "Test notification"

# Check Lambda function logs (for Slack notifications)
aws logs tail /aws/lambda/slack-notifications --follow
```

## Best Practices

### Alarm Configuration
1. **Use Appropriate Evaluation Periods**: Balance responsiveness with false positive reduction
2. **Set Realistic Thresholds**: Base thresholds on historical performance data
3. **Implement Escalation**: Use escalation for critical production systems
4. **Tag Alarms**: Use consistent tagging for management and cost tracking

### Notification Management
1. **Avoid Notification Fatigue**: Use composite alarms to reduce noise
2. **Test Notification Channels**: Regularly test all notification methods
3. **Document Escalation Procedures**: Maintain clear escalation documentation
4. **Monitor Notification Costs**: Track SNS and Lambda costs for notifications

### Monitoring Strategy
1. **Layer Monitoring**: Use multiple alarm types for comprehensive coverage
2. **Environment-Specific Configuration**: Adjust settings based on environment criticality
3. **Regular Review**: Periodically review and adjust alarm configurations
4. **Automate Testing**: Implement automated alarm testing in CI/CD pipelines

## Security Considerations

### IAM Permissions
- **Least Privilege**: Grant minimal required permissions
- **Service Roles**: Use service-specific IAM roles
- **Cross-Service Access**: Properly configure cross-service permissions

### Sensitive Data
- **Webhook URLs**: Store Slack webhook URLs securely
- **Email Addresses**: Validate email addresses to prevent information disclosure
- **Encryption**: Use encryption for SNS topics and Lambda environment variables

### Access Control
- **Alarm Management**: Restrict alarm modification permissions
- **Notification Access**: Control access to notification channels
- **Audit Logging**: Enable CloudTrail for alarm management actions