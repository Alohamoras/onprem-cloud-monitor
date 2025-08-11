# Error Handling and Logging Guide

This guide explains the comprehensive error handling and logging strategy implemented in the CloudWatch Synthetics canary scripts.

## Overview

The canary scripts implement a simple but effective error handling strategy that focuses on:

- **Detailed error categorization** for better troubleshooting
- **Structured logging** for easy analysis
- **Simple retry logic** without exponential backoff
- **CloudWatch alarms** handle sophisticated alerting patterns
- **Custom metrics** for comprehensive monitoring

## Error Categories

### Network Errors (`NETWORK_ERROR`)
- **ECONNREFUSED**: Connection refused by target
- **ECONNRESET**: Connection reset by peer
- **ENETUNREACH**: Network unreachable
- **EHOSTUNREACH**: Host unreachable

**Common Causes:**
- Target service is down
- Firewall blocking connections
- Network routing issues
- Security group misconfiguration

### DNS Errors (`DNS_ERROR`)
- **ENOTFOUND**: DNS resolution failed
- **EAI_AGAIN**: DNS lookup timeout

**Common Causes:**
- Invalid hostname
- DNS server issues
- VPC DNS configuration problems

### Timeout Errors (`TIMEOUT_ERROR`)
- **ETIMEDOUT**: Connection timeout
- **ESOCKETTIMEDOUT**: Socket timeout
- **REQUEST_TIMEOUT**: Request timeout

**Common Causes:**
- Slow network connectivity
- Target service overloaded
- Timeout values too low

### HTTP Errors (`HTTP_ERROR`)
- Unexpected HTTP status codes
- HTTP protocol errors

**Common Causes:**
- Service returning error responses
- Authentication failures
- API endpoint changes

### Content Errors (`CONTENT_ERROR`)
- Content validation failures
- Response parsing errors

**Common Causes:**
- API response format changes
- Content validation patterns outdated
- Encoding issues

### Configuration Errors (`CONFIG_ERROR`)
- Invalid endpoint URLs
- Invalid configuration parameters

**Common Causes:**
- Misconfigured environment variables
- Invalid URL formats
- Parameter validation failures

## Logging Strategy

### Structured Logging

All log entries use a structured JSON format:

```json
{
  "timestamp": "2024-01-15T10:30:00.000Z",
  "level": "INFO",
  "message": "API check successful",
  "canaryName": "my-api-canary",
  "attempt": 1,
  "endpoint": "https://api.example.com",
  "responseTime": 245,
  "statusCode": 200,
  "performanceCategory": "FAST"
}
```

### Log Levels

- **DEBUG**: Detailed request/response information
- **INFO**: Normal operation events
- **WARN**: Retry attempts and recoverable errors
- **ERROR**: Failures and critical issues

### Performance Categories

Response times are categorized for easy analysis:

#### Heartbeat Canary
- **FAST**: < 1 second
- **NORMAL**: 1-3 seconds
- **SLOW**: 3-10 seconds
- **VERY_SLOW**: > 10 seconds

#### API Canary
- **FAST**: < 0.5 seconds
- **NORMAL**: 0.5-2 seconds
- **SLOW**: 2-5 seconds
- **VERY_SLOW**: > 5 seconds

## Retry Strategy

### Simple Retry Logic

The canaries implement simple retry logic without exponential backoff:

```javascript
for (let attempt = 1; attempt <= config.retries; attempt++) {
    try {
        // Perform test
        return result;
    } catch (error) {
        if (attempt < config.retries) {
            await sleep(config.retryDelay); // Fixed delay
        }
    }
}
```

### Why No Exponential Backoff?

1. **CloudWatch Alarms Handle Alerting**: Sophisticated alerting patterns are handled by CloudWatch alarms, not the canary scripts
2. **Simplicity**: Simple retry logic is more predictable and easier to debug
3. **Consistent Timing**: Fixed delays provide consistent monitoring intervals
4. **Resource Efficiency**: Avoids unnecessary complexity in Lambda functions

### Configuration Parameters

- **retries**: Number of retry attempts (1-5, default: 3)
- **retryDelay**: Fixed delay between retries (500ms minimum, default: 1000ms)

## Custom Metrics

### Heartbeat Canary Metrics

| Metric Name | Description | Unit |
|-------------|-------------|------|
| `HeartbeatSuccess` | Successful heartbeat checks | Count |
| `HeartbeatFailure` | Failed heartbeat attempts | Count |
| `HeartbeatTotalFailure` | Complete heartbeat failures | Count |
| `ResponseTime` | Response time in milliseconds | Milliseconds |
| `AttemptsRequired` | Number of attempts needed | Count |
| `Performance_FAST` | Fast responses (< 1s) | Count |
| `Performance_NORMAL` | Normal responses (1-3s) | Count |
| `Performance_SLOW` | Slow responses (3-10s) | Count |
| `Performance_VERY_SLOW` | Very slow responses (> 10s) | Count |
| `Error_NETWORK_ERROR` | Network-related errors | Count |
| `Error_DNS_ERROR` | DNS-related errors | Count |
| `Error_TIMEOUT_ERROR` | Timeout-related errors | Count |
| `StatusCode_200` | HTTP 200 responses | Count |
| `ExecutionTime` | Total canary execution time | Milliseconds |
| `CanarySuccess` | Successful canary executions | Count |
| `CanaryFailure` | Failed canary executions | Count |

### API Canary Metrics

| Metric Name | Description | Unit |
|-------------|-------------|------|
| `ApiSuccess` | Successful API checks | Count |
| `ApiFailure` | Failed API attempts | Count |
| `ApiTotalFailure` | Complete API failures | Count |
| `ApiResponseTime` | API response time | Milliseconds |
| `ApiContentLength` | Response content length | Bytes |
| `ApiPerformance_FAST` | Fast API responses (< 0.5s) | Count |
| `ApiPerformance_NORMAL` | Normal API responses (0.5-2s) | Count |
| `ApiPerformance_SLOW` | Slow API responses (2-5s) | Count |
| `ApiPerformance_VERY_SLOW` | Very slow API responses (> 5s) | Count |
| `ApiStatusCode_200` | HTTP 200 responses | Count |
| `ApiRedirects` | Number of redirects followed | Count |
| `ApiContentValidated` | Content validation successes | Count |
| `ApiError_CONTENT_ERROR` | Content validation errors | Count |
| `ApiExecutionTime` | Total API canary execution time | Milliseconds |

## CloudWatch Integration

### Log Groups

Canary logs are automatically sent to CloudWatch Logs:
- **Log Group**: `/aws/lambda/cwsyn-{canary-name}-{random-id}`
- **Retention**: Configurable (default: 30 days)

### Custom Metrics Namespace

All custom metrics are published to:
- **Namespace**: `CloudWatchSynthetics/UserAgentMetrics`
- **Dimensions**: `CanaryName`

### Querying Logs

Use CloudWatch Logs Insights to query structured logs:

```sql
-- Find all errors in the last hour
fields @timestamp, level, message, errorCategory, error
| filter level = "ERROR"
| sort @timestamp desc
| limit 100

-- Analyze performance trends
fields @timestamp, responseTime, performanceCategory
| filter level = "INFO" and message = "API check successful"
| stats avg(responseTime) by bin(5m)

-- Error categorization
fields @timestamp, errorCategory
| filter level = "ERROR"
| stats count() by errorCategory
```

## Troubleshooting Guide

### High Error Rates

1. **Check Error Categories**: Identify the most common error types
2. **Review Network Configuration**: Verify VPC, security groups, and routing
3. **Validate Target Health**: Ensure target services are operational
4. **Check DNS Resolution**: Verify hostname resolution from VPC

### Slow Response Times

1. **Review Performance Metrics**: Check performance category distribution
2. **Network Latency**: Test network connectivity from VPC
3. **Target Performance**: Monitor target service performance
4. **Timeout Configuration**: Adjust timeout values if needed

### Configuration Issues

1. **Validate Environment Variables**: Check all configuration parameters
2. **URL Format**: Ensure endpoint URLs are properly formatted
3. **Expected Status Codes**: Verify expected response codes
4. **Content Patterns**: Update content validation patterns

### CloudWatch Alarms Not Triggering

1. **Metric Availability**: Verify custom metrics are being published
2. **Alarm Configuration**: Check alarm thresholds and evaluation periods
3. **Missing Data Treatment**: Review how alarms handle missing data
4. **SNS Topics**: Verify notification topics are properly configured

## Best Practices

### Configuration

1. **Reasonable Timeouts**: Set timeouts appropriate for your network and services
2. **Limited Retries**: Use 2-3 retries to balance reliability and execution time
3. **Appropriate Delays**: Use 1-2 second delays between retries
4. **Validate Configuration**: Always validate configuration parameters

### Monitoring

1. **Use CloudWatch Dashboards**: Create dashboards for key metrics
2. **Set Up Alarms**: Configure alarms for different error categories
3. **Regular Review**: Periodically review logs and metrics
4. **Trend Analysis**: Monitor performance trends over time

### Alerting

1. **Layered Alerting**: Use different thresholds for warnings and critical alerts
2. **Error Category Alarms**: Create specific alarms for different error types
3. **Composite Alarms**: Use composite alarms for overall health status
4. **Escalation Paths**: Configure appropriate escalation for critical issues

## Example Configurations

### Development Environment
```javascript
{
  "timeout": 15000,
  "retries": 2,
  "retryDelay": 1000,
  "expectedStatusCodes": [200, 201, 202]
}
```

### Production Environment
```javascript
{
  "timeout": 10000,
  "retries": 3,
  "retryDelay": 1500,
  "expectedStatusCodes": [200],
  "validateContent": true,
  "expectedContentPattern": "status.*ok"
}
```

This error handling strategy provides comprehensive monitoring while keeping the canary scripts simple and reliable. CloudWatch alarms handle the sophisticated alerting logic, allowing the canaries to focus on accurate monitoring and detailed reporting.