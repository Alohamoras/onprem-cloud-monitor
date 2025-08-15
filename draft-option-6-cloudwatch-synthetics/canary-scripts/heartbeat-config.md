# Heartbeat Canary Configuration

## Environment Variables

The heartbeat canary script supports the following environment variables for configuration:

### Required Variables

- `TARGET_ENDPOINT` - The endpoint to monitor (e.g., `http://10.0.1.100:8080` or `https://api.example.com`)

### Optional Variables

- `TIMEOUT` - Request timeout in milliseconds (default: 30000)
- `RETRIES` - Number of retry attempts on failure (default: 3)
- `RETRY_DELAY` - Delay between retries in milliseconds (default: 1000)
- `EXPECTED_STATUS_CODES` - Comma-separated list of acceptable HTTP status codes (default: "200,201,202,204")
- `USER_AGENT` - Custom User-Agent header (default: "AWS-Synthetics-Heartbeat-Canary/1.0")

## Example Configurations

### Basic On-Premises Device Monitoring
```bash
TARGET_ENDPOINT=http://192.168.1.100:8080
TIMEOUT=15000
RETRIES=2
```

### Snowball S3 Endpoint Monitoring
```bash
TARGET_ENDPOINT=http://10.0.1.50:8080
TIMEOUT=10000
RETRIES=3
EXPECTED_STATUS_CODES=200,403
USER_AGENT=Snowball-Monitor/1.0
```

### High-Availability Service Monitoring
```bash
TARGET_ENDPOINT=https://critical-service.internal:443
TIMEOUT=5000
RETRIES=5
RETRY_DELAY=2000
EXPECTED_STATUS_CODES=200,201,202
```

## CloudFormation Environment Variable Configuration

When deploying via CloudFormation, configure environment variables in the canary resource:

```yaml
SyntheticsCanary:
  Type: AWS::Synthetics::Canary
  Properties:
    # ... other properties
    RunConfig:
      EnvironmentVariables:
        TARGET_ENDPOINT: !Ref TargetEndpoint
        TIMEOUT: !Ref RequestTimeout
        RETRIES: !Ref RetryAttempts
        EXPECTED_STATUS_CODES: !Ref ExpectedStatusCodes
```

## CDK Environment Variable Configuration

When using CDK, configure environment variables:

```typescript
new synthetics.Canary(this, 'HeartbeatCanary', {
  // ... other properties
  environmentVariables: {
    TARGET_ENDPOINT: props.targetEndpoint,
    TIMEOUT: props.timeout.toString(),
    RETRIES: props.retries.toString(),
    EXPECTED_STATUS_CODES: props.expectedStatusCodes.join(',')
  }
});
```

## Error Types and Troubleshooting

The canary categorizes different types of errors for easier troubleshooting:

- `CONNECTION_REFUSED` - Target service is not running or port is closed
- `DNS_RESOLUTION_FAILED` - Hostname cannot be resolved
- `CONNECTION_TIMEOUT` - Network connectivity issues or slow response
- `CONNECTION_RESET` - Connection was reset by the target
- `REQUEST_TIMEOUT` - Request exceeded the configured timeout
- `REQUEST_SETUP_ERROR` - Error in request configuration
- `UNKNOWN_ERROR` - Other network or system errors

## Custom Metrics

The canary publishes the following custom CloudWatch metrics:

- `HeartbeatSuccess` - Successful connectivity test (value: 1)
- `HeartbeatFailure` - Failed connectivity test attempt (value: 1)
- `HeartbeatTotalFailure` - Complete failure after all retries (value: 1)
- `ResponseTime` - Response time in milliseconds
- `AttemptsRequired` - Number of attempts needed for success