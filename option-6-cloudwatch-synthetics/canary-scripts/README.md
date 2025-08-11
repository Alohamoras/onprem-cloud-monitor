# Canary Scripts

This directory contains Node.js scripts for CloudWatch Synthetics monitoring of on-premises devices and endpoints.

## Available Canary Scripts

### Heartbeat Canary (`heartbeat-canary.js`)

A comprehensive heartbeat monitoring script that performs basic connectivity testing to on-premises endpoints with configurable timeout and retry logic.

### API Canary (`api-canary.js`)

A specialized HTTP-based endpoint testing script designed specifically for Snowball S3 endpoint monitoring with advanced validation capabilities.

**Features:**
- Configurable timeout and retry mechanisms
- Support for HTTP and HTTPS endpoints
- Environment variable configuration
- Detailed error categorization and logging
- Custom CloudWatch metrics
- Network connectivity issue detection

**Usage:**
```javascript
// The canary is designed to run in AWS CloudWatch Synthetics environment
// Configure via environment variables (see heartbeat-config.md)
```

**Environment Variables:**
- `TARGET_ENDPOINT` - The endpoint to monitor (required)
- `TIMEOUT` - Request timeout in milliseconds (default: 30000)
- `RETRIES` - Number of retry attempts (default: 3)
- `RETRY_DELAY` - Delay between retries in milliseconds (default: 1000)
- `EXPECTED_STATUS_CODES` - Acceptable HTTP status codes (default: "200,201,202,204")
- `USER_AGENT` - Custom User-Agent header

**Features:**
- Configurable timeout and retry mechanisms
- Support for HTTP and HTTPS endpoints
- Environment variable configuration
- Detailed error categorization and logging
- Custom CloudWatch metrics
- Network connectivity issue detection

### API Canary (`api-canary.js`)

**Features:**
- HTTP GET requests to Snowball S3 endpoints (http://ip:8080)
- Configurable expected status codes and response timeouts
- Custom HTTP headers support for authentication
- Response time measurement and content validation logic
- Response size limits to prevent memory issues
- Redirect following for load-balanced setups
- Comprehensive error handling and categorization

**Environment Variables:**
- `API_ENDPOINT` - The API endpoint URL to monitor (required)
- `EXPECTED_STATUS` - Expected HTTP status code (default: 200)
- `REQUEST_TIMEOUT` - Request timeout in milliseconds (default: 10000)
- `RETRIES` - Number of retry attempts (default: 3)
- `CUSTOM_HEADERS` - JSON string of custom HTTP headers
- `VALIDATE_CONTENT` - Enable response content validation (default: false)
- `EXPECTED_CONTENT_PATTERN` - Pattern to match in response content
- `FOLLOW_REDIRECTS` - Enable automatic redirect following (default: false)
- `MAX_RESPONSE_SIZE` - Maximum response size in bytes (default: 1MB)

See `api-canary-config.md` for detailed configuration examples.

## Testing

### Local Testing

You can test both canaries locally using the provided test scripts:

```bash
# Test heartbeat canary
node test-heartbeat.js

# Test API canary (all scenarios)
node test-api-canary.js

# Test specific API canary scenario
node test-api-canary.js "snowball"
```

**Available npm scripts:**
```bash
npm run test-heartbeat      # Test heartbeat canary
npm run test-api           # Test API canary (all scenarios)
npm run test-api-basic     # Test basic API scenario
npm run test-api-content   # Test content validation scenario
```

### Custom Testing

To test against your own endpoint, modify the environment variables in `test-heartbeat.js`:

```javascript
process.env.TARGET_ENDPOINT = 'http://your-endpoint:8080';
process.env.TIMEOUT = '15000';
process.env.RETRIES = '3';
```

## Deployment

These canary scripts are designed to be deployed using:
1. AWS CloudFormation templates (see `../infrastructure/cloudformation/`)
2. AWS CDK (see `../infrastructure/cdk/`)
3. Manual deployment via AWS Console

## Error Handling

The heartbeat canary provides detailed error categorization:

- **CONNECTION_REFUSED** - Service not running or port closed
- **DNS_RESOLUTION_FAILED** - Hostname resolution issues
- **CONNECTION_TIMEOUT** - Network connectivity problems
- **CONNECTION_RESET** - Connection reset by target
- **REQUEST_TIMEOUT** - Request exceeded timeout
- **REQUEST_SETUP_ERROR** - Configuration errors
- **UNKNOWN_ERROR** - Other system errors

## Custom Metrics

### Heartbeat Canary Metrics
- `HeartbeatSuccess` - Successful tests
- `HeartbeatFailure` - Failed test attempts
- `HeartbeatTotalFailure` - Complete failures after all retries
- `ResponseTime` - Response time in milliseconds
- `AttemptsRequired` - Number of attempts needed

### API Canary Metrics
- `ApiSuccess` - Successful API calls
- `ApiFailure` - Failed API call attempts
- `ApiTotalFailure` - Complete failures after all retries
- `ApiResponseTime` - Response time in milliseconds
- `ApiContentLength` - Response content length in bytes
- `AttemptsRequired` - Number of attempts needed

## Requirements Satisfied

### Heartbeat Canary
- **1.1**: Canary pings on-premises devices at defined intervals
- **1.2**: Records failures in CloudWatch metrics
- **4.2**: Provides Node.js script for basic connectivity tests

### API Canary
- **1.1**: Monitors on-premises devices using CloudWatch Synthetics canaries
- **4.3**: Provides Node.js API canary script for HTTP-based endpoint testing
- **4.4**: Implements HTTP GET requests to Snowball S3 endpoint with response validation
- **4.4**: Includes configurable parameters for status codes, timeouts, and custom headers
- **4.4**: Features response time measurement and content validation logic

## Next Steps

With both heartbeat and API canaries implemented:
1. Deploy using infrastructure templates (CloudFormation/CDK)
2. Configure CloudWatch alarms based on the custom metrics
3. Set up SNS notifications for failure alerts
4. Create comprehensive deployment documentation
5. Implement cost optimization strategies