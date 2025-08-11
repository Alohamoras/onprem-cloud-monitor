# API Canary Configuration Guide

## Overview

The API canary script (`api-canary.js`) is designed specifically for HTTP-based endpoint testing, with particular focus on Snowball S3 endpoint monitoring. It provides comprehensive configuration options for status code validation, response timeouts, custom headers, and content validation.

## Environment Variables

### Required Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `API_ENDPOINT` | `http://localhost:8080` | The target API endpoint URL to monitor |
| `EXPECTED_STATUS` | `200` | Expected HTTP status code for successful requests |
| `REQUEST_TIMEOUT` | `10000` | Request timeout in milliseconds |

### Optional Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `RETRIES` | `3` | Number of retry attempts on failure |
| `RETRY_DELAY` | `1000` | Delay between retries in milliseconds |
| `CUSTOM_HEADERS` | `{}` | JSON string of custom HTTP headers |
| `VALIDATE_CONTENT` | `false` | Enable response content validation |
| `EXPECTED_CONTENT_PATTERN` | `null` | Pattern to match in response content |
| `MAX_RESPONSE_SIZE` | `1048576` | Maximum response size in bytes (1MB) |
| `USER_AGENT` | `AWS-Synthetics-API-Canary/1.0` | Custom User-Agent header |
| `FOLLOW_REDIRECTS` | `false` | Enable automatic redirect following |
| `MAX_REDIRECTS` | `5` | Maximum number of redirects to follow |

## Configuration Examples

### Basic Snowball S3 Endpoint Monitoring

```bash
# Environment variables for basic S3 endpoint monitoring
export API_ENDPOINT="http://192.168.1.100:8080"
export EXPECTED_STATUS="200"
export REQUEST_TIMEOUT="15000"
export RETRIES="3"
export USER_AGENT="Snowball-S3-Monitor/1.0"
```

### S3 Endpoint with Authentication Headers

```bash
# S3 endpoint with custom authentication
export API_ENDPOINT="http://192.168.1.100:8080/bucket-name"
export EXPECTED_STATUS="200"
export CUSTOM_HEADERS='{"Authorization": "AWS4-HMAC-SHA256 ...", "x-amz-date": "20231201T120000Z"}'
export REQUEST_TIMEOUT="20000"
```

### Content Validation for S3 Responses

```bash
# Validate that S3 response contains expected content
export API_ENDPOINT="http://192.168.1.100:8080/bucket-name"
export EXPECTED_STATUS="200"
export VALIDATE_CONTENT="true"
export EXPECTED_CONTENT_PATTERN="ListBucketResult"
export MAX_RESPONSE_SIZE="2097152"  # 2MB for larger S3 responses
```

### High-Availability S3 Endpoint with Redirects

```bash
# S3 endpoint that may redirect to different nodes
export API_ENDPOINT="http://snowball-lb.local:8080"
export EXPECTED_STATUS="200"
export FOLLOW_REDIRECTS="true"
export MAX_REDIRECTS="3"
export REQUEST_TIMEOUT="30000"
```

## CloudFormation Template Integration

When using this canary in CloudFormation templates, configure the environment variables in the canary resource:

```yaml
SyntheticsCanary:
  Type: AWS::Synthetics::Canary
  Properties:
    Name: !Sub "${AWS::StackName}-s3-api-canary"
    Code:
      Handler: api-canary.handler
      Script: !Sub |
        # Canary script content here
    RuntimeVersion: syn-nodejs-puppeteer-6.2
    Schedule:
      Expression: rate(5 minutes)
    EnvironmentVariables:
      API_ENDPOINT: !Ref S3EndpointUrl
      EXPECTED_STATUS: "200"
      REQUEST_TIMEOUT: "15000"
      RETRIES: "3"
      CUSTOM_HEADERS: !Sub '{"Host": "${S3EndpointHost}:8080"}'
      USER_AGENT: "Snowball-S3-Monitor/1.0"
```

## CDK Integration Example

```typescript
import { Canary, Code, Runtime, Schedule } from 'aws-cdk-lib/aws-synthetics';

const apiCanary = new Canary(this, 'S3ApiCanary', {
  canaryName: 'snowball-s3-api-monitor',
  code: Code.fromAsset('canary-scripts'),
  handler: 'api-canary.handler',
  runtime: Runtime.SYNTHETICS_NODEJS_PUPPETEER_6_2,
  schedule: Schedule.rate(Duration.minutes(5)),
  environmentVariables: {
    API_ENDPOINT: 'http://192.168.1.100:8080',
    EXPECTED_STATUS: '200',
    REQUEST_TIMEOUT: '15000',
    RETRIES: '3',
    USER_AGENT: 'Snowball-S3-Monitor/1.0'
  }
});
```

## Monitoring Metrics

The API canary generates the following custom CloudWatch metrics:

- `ApiSuccess`: Number of successful API calls
- `ApiFailure`: Number of failed API calls  
- `ApiTotalFailure`: Number of total failures after all retries
- `ApiResponseTime`: Response time in milliseconds
- `ApiContentLength`: Response content length in bytes
- `AttemptsRequired`: Number of attempts needed for success

## Error Categories

The canary categorizes errors for better troubleshooting:

- `CONNECTION_REFUSED`: Target endpoint is not accepting connections
- `DNS_RESOLUTION_FAILED`: Cannot resolve the endpoint hostname
- `CONNECTION_TIMEOUT`: Connection attempt timed out
- `CONNECTION_RESET`: Connection was reset by the target
- `SSL_CERTIFICATE_EXPIRED`: SSL certificate has expired
- `SSL_CERTIFICATE_INVALID`: SSL certificate is invalid
- `REQUEST_TIMEOUT`: Request exceeded the configured timeout
- `UNKNOWN_ERROR`: Unrecognized error type

## Testing

### Local Testing

Run the test script to validate canary functionality:

```bash
# Run all test scenarios
node test-api-canary.js

# Run a specific test scenario
node test-api-canary.js "snowball"
```

### Available Test Scenarios

1. **Basic S3 Endpoint Test**: Simple HTTP GET request validation
2. **S3 Endpoint with Custom Headers**: Testing with authentication headers
3. **S3 Endpoint with Content Validation**: Response content pattern matching
4. **S3 Endpoint with Redirect Following**: Handling redirects in load-balanced setups
5. **Snowball S3 Endpoint Simulation**: Realistic Snowball S3 configuration

## Best Practices

1. **Timeout Configuration**: Set appropriate timeouts based on network latency to on-premises infrastructure
2. **Retry Logic**: Configure retries to handle transient network issues
3. **Content Validation**: Use content validation for critical endpoints to ensure functionality beyond connectivity
4. **Custom Headers**: Include necessary authentication headers for secured S3 endpoints
5. **Response Size Limits**: Set appropriate response size limits to prevent memory issues
6. **Monitoring Frequency**: Balance monitoring frequency with cost considerations

## Troubleshooting

### Common Issues

1. **Connection Refused**: Check if the S3 endpoint is running and accessible
2. **DNS Resolution Failed**: Verify hostname resolution from the canary's VPC
3. **Timeout Issues**: Increase timeout values for slow network connections
4. **Content Validation Failures**: Verify the expected content pattern matches actual responses
5. **SSL Certificate Issues**: Ensure certificates are valid and trusted

### Debug Mode

Enable detailed logging by setting log level in the canary configuration:

```javascript
// Add to canary script for debugging
log.info('Debug: Request details', {
    endpoint: config.apiEndpoint,
    headers: config.customHeaders,
    timeout: config.requestTimeout
});
```