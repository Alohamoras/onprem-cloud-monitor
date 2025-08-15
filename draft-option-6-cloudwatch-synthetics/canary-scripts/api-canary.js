const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');
const https = require('https');
const http = require('http');
const { URL } = require('url');

/**
 * API Canary Script for S3 Endpoint Monitoring
 * 
 * This canary performs HTTP-based endpoint testing specifically for Snowball S3 endpoints
 * with enhanced error handling, detailed logging, and comprehensive metrics.
 * 
 * Error handling strategy:
 * - Simple retry logic (no exponential backoff)
 * - Detailed error categorization and logging
 * - CloudWatch alarms handle sophisticated alerting
 * - Custom metrics for API-specific monitoring insights
 */

// Error categories for detailed monitoring
const ERROR_CATEGORIES = {
    NETWORK: 'NETWORK_ERROR',
    DNS: 'DNS_ERROR', 
    TIMEOUT: 'TIMEOUT_ERROR',
    HTTP: 'HTTP_ERROR',
    CONTENT: 'CONTENT_ERROR',
    CONFIG: 'CONFIG_ERROR',
    UNKNOWN: 'UNKNOWN_ERROR'
};

// Performance thresholds for API responses
const PERFORMANCE_THRESHOLDS = {
    FAST: 500,       // < 0.5s
    NORMAL: 2000,    // 0.5-2s
    SLOW: 5000,      // 2-5s
    VERY_SLOW: 15000 // > 5s
};

/**
 * Enhanced logging utility with structured output
 */
function logStructured(level, message, data = {}) {
    const logEntry = {
        timestamp: new Date().toISOString(),
        level: level.toUpperCase(),
        message,
        canaryName: process.env.AWS_LAMBDA_FUNCTION_NAME || 'api-canary',
        ...data
    };
    
    log[level](JSON.stringify(logEntry));
}

/**
 * Categorize error based on error code and message
 */
function categorizeError(error) {
    if (!error || !error.code) {
        if (error && error.message) {
            if (error.message.includes('Content validation failed')) {
                return ERROR_CATEGORIES.CONTENT;
            }
            if (error.message.includes('status code')) {
                return ERROR_CATEGORIES.HTTP;
            }
        }
        return ERROR_CATEGORIES.UNKNOWN;
    }
    
    const errorCode = error.code.toLowerCase();
    
    if (['econnrefused', 'econnreset', 'enetunreach', 'ehostunreach'].includes(errorCode)) {
        return ERROR_CATEGORIES.NETWORK;
    }
    
    if (['enotfound', 'eai_again'].includes(errorCode)) {
        return ERROR_CATEGORIES.DNS;
    }
    
    if (['etimedout', 'esockettimedout'].includes(errorCode)) {
        return ERROR_CATEGORIES.TIMEOUT;
    }
    
    return ERROR_CATEGORIES.UNKNOWN;
}

/**
 * Categorize performance based on response time
 */
function categorizePerformance(responseTime) {
    if (responseTime < PERFORMANCE_THRESHOLDS.FAST) return 'FAST';
    if (responseTime < PERFORMANCE_THRESHOLDS.NORMAL) return 'NORMAL';
    if (responseTime < PERFORMANCE_THRESHOLDS.SLOW) return 'SLOW';
    return 'VERY_SLOW';
}

const apiCheck = async function () {
    // Configuration from environment variables with validation
    const config = {
        apiEndpoint: process.env.API_ENDPOINT || 'http://localhost:8080',
        expectedStatusCode: parseInt(process.env.EXPECTED_STATUS) || 200,
        requestTimeout: Math.max(1000, parseInt(process.env.REQUEST_TIMEOUT) || 10000),
        retries: Math.max(1, Math.min(5, parseInt(process.env.RETRIES) || 3)),
        retryDelay: Math.max(500, parseInt(process.env.RETRY_DELAY) || 1000),
        customHeaders: parseCustomHeaders(process.env.CUSTOM_HEADERS),
        validateContent: process.env.VALIDATE_CONTENT === 'true',
        expectedContentPattern: process.env.EXPECTED_CONTENT_PATTERN || null,
        maxResponseSize: Math.max(1024, parseInt(process.env.MAX_RESPONSE_SIZE) || 1024 * 1024),
        userAgent: process.env.USER_AGENT || 'AWS-Synthetics-API-Canary/1.0',
        followRedirects: process.env.FOLLOW_REDIRECTS !== 'false', // Default to true
        maxRedirects: Math.max(1, Math.min(10, parseInt(process.env.MAX_REDIRECTS) || 5))
    };

    // Validate configuration
    try {
        new URL(config.apiEndpoint);
    } catch (error) {
        logStructured('error', 'Invalid API endpoint URL configuration', { 
            endpoint: config.apiEndpoint, 
            error: error.message 
        });
        throw new Error(`CONFIG_ERROR: Invalid API endpoint URL: ${config.apiEndpoint}`);
    }

    if (config.expectedStatusCode < 100 || config.expectedStatusCode > 599) {
        throw new Error(`CONFIG_ERROR: Invalid expected status code: ${config.expectedStatusCode}`);
    }

    logStructured('info', 'Starting API check', { 
        config: {
            ...config,
            // Don't log sensitive headers
            customHeaders: config.customHeaders ? Object.keys(config.customHeaders) : [],
            userAgent: config.userAgent.substring(0, 50) + '...'
        }
    });

    return await synthetics.executeStep('api-endpoint-test', async function() {
        let lastError = null;
        let errorCategory = ERROR_CATEGORIES.UNKNOWN;
        const attemptResults = [];
        
        for (let attempt = 1; attempt <= config.retries; attempt++) {
            const attemptStartTime = Date.now();
            
            try {
                logStructured('info', 'Starting API test attempt', {
                    attempt,
                    totalAttempts: config.retries,
                    endpoint: config.apiEndpoint,
                    expectedStatus: config.expectedStatusCode,
                    timeout: config.requestTimeout
                });
                
                const result = await performApiTest(config);
                const performanceCategory = categorizePerformance(result.responseTime);
                
                // Log successful API call with detailed metrics
                logStructured('info', 'API check successful', {
                    attempt,
                    endpoint: config.apiEndpoint,
                    responseTime: result.responseTime,
                    statusCode: result.statusCode,
                    contentLength: result.contentLength,
                    performanceCategory,
                    redirectCount: result.redirectCount || 0,
                    contentValidated: result.contentValidated
                });

                // Add comprehensive custom metrics
                await synthetics.addUserAgentMetric('ApiSuccess', 1);
                await synthetics.addUserAgentMetric('ApiResponseTime', result.responseTime);
                await synthetics.addUserAgentMetric('ApiContentLength', result.contentLength || 0);
                await synthetics.addUserAgentMetric('AttemptsRequired', attempt);
                await synthetics.addUserAgentMetric(`ApiPerformance_${performanceCategory}`, 1);
                await synthetics.addUserAgentMetric('ApiStatusCode_' + result.statusCode, 1);
                
                if (result.redirectCount > 0) {
                    await synthetics.addUserAgentMetric('ApiRedirects', result.redirectCount);
                }
                
                if (result.contentValidated) {
                    await synthetics.addUserAgentMetric('ApiContentValidated', 1);
                }

                // Add success result to attempts log
                attemptResults.push({
                    attempt,
                    success: true,
                    responseTime: result.responseTime,
                    statusCode: result.statusCode,
                    contentLength: result.contentLength,
                    performanceCategory,
                    redirectCount: result.redirectCount
                });

                return {
                    ...result,
                    attemptResults,
                    totalAttempts: attempt,
                    performanceCategory
                };
                
            } catch (error) {
                lastError = error;
                errorCategory = categorizeError(error);
                const attemptDuration = Date.now() - attemptStartTime;
                
                logStructured('warn', 'API test attempt failed', {
                    attempt,
                    totalAttempts: config.retries,
                    error: error.message,
                    errorCategory,
                    attemptDuration,
                    willRetry: attempt < config.retries
                });
                
                // Add failure metrics with categorization
                await synthetics.addUserAgentMetric('ApiFailure', 1);
                await synthetics.addUserAgentMetric(`ApiError_${errorCategory}`, 1);
                
                // Add failed result to attempts log
                attemptResults.push({
                    attempt,
                    success: false,
                    error: error.message,
                    errorCategory,
                    attemptDuration
                });
                
                // Simple retry logic - wait before retry (except on last attempt)
                if (attempt < config.retries) {
                    logStructured('info', 'Waiting before retry', {
                        retryDelay: config.retryDelay,
                        nextAttempt: attempt + 1
                    });
                    await sleep(config.retryDelay);
                }
            }
        }
        
        // All retries exhausted - log comprehensive failure details
        logStructured('error', 'API check failed after all retries', {
            totalAttempts: config.retries,
            lastError: lastError.message,
            errorCategory,
            attemptResults,
            endpoint: config.apiEndpoint
        });
        
        // Add final failure metrics
        await synthetics.addUserAgentMetric('ApiTotalFailure', 1);
        await synthetics.addUserAgentMetric('AttemptsRequired', config.retries);
        await synthetics.addUserAgentMetric(`ApiFinalError_${errorCategory}`, 1);
        
        // Create detailed error message
        const errorMessage = `${errorCategory}: API check failed after ${config.retries} attempts. Last error: ${lastError.message}`;
        throw new Error(errorMessage);
    });
};

/**
 * Performs the actual API test to the target endpoint
 */
async function performApiTest(config) {
    return new Promise((resolve, reject) => {
        const startTime = Date.now();
        let redirectCount = 0;
        
        function makeRequest(url) {
            try {
                const parsedUrl = new URL(url);
                const isHttps = parsedUrl.protocol === 'https:';
                const client = isHttps ? https : http;
                
                const requestOptions = {
                    hostname: parsedUrl.hostname,
                    port: parsedUrl.port || (isHttps ? 443 : 80),
                    path: parsedUrl.pathname + parsedUrl.search,
                    method: 'GET',
                    timeout: config.requestTimeout,
                    headers: {
                        'User-Agent': config.userAgent,
                        'Accept': '*/*',
                        'Connection': 'close',
                        ...config.customHeaders
                    }
                };

                log.info('Making API request with options:', JSON.stringify(requestOptions, null, 2));

                const req = client.request(requestOptions, (res) => {
                    const responseTime = Date.now() - startTime;
                    
                    log.info(`Received API response: ${res.statusCode} in ${responseTime}ms`);
                    
                    // Handle redirects
                    if (config.followRedirects && (res.statusCode === 301 || res.statusCode === 302 || res.statusCode === 307 || res.statusCode === 308)) {
                        if (redirectCount >= config.maxRedirects) {
                            reject(new Error(`Too many redirects: exceeded maximum of ${config.maxRedirects}`));
                            return;
                        }
                        
                        const location = res.headers.location;
                        if (!location) {
                            reject(new Error(`Redirect response missing Location header`));
                            return;
                        }
                        
                        redirectCount++;
                        log.info(`Following redirect ${redirectCount}/${config.maxRedirects} to: ${location}`);
                        
                        // Consume response data before following redirect
                        res.on('data', () => {});
                        res.on('end', () => {
                            makeRequest(location);
                        });
                        return;
                    }
                    
                    // Check if status code matches expected
                    if (res.statusCode !== config.expectedStatusCode) {
                        reject(new Error(`Unexpected status code: ${res.statusCode}. Expected: ${config.expectedStatusCode}`));
                        return;
                    }
                    
                    // Collect response data for content validation
                    let responseData = '';
                    let contentLength = 0;
                    
                    res.on('data', (chunk) => {
                        contentLength += chunk.length;
                        
                        // Prevent memory issues with large responses
                        if (contentLength > config.maxResponseSize) {
                            reject(new Error(`Response too large: ${contentLength} bytes exceeds maximum of ${config.maxResponseSize} bytes`));
                            return;
                        }
                        
                        // Only collect data if content validation is enabled
                        if (config.validateContent) {
                            responseData += chunk.toString();
                        }
                    });
                    
                    res.on('end', () => {
                        try {
                            // Perform content validation if enabled
                            if (config.validateContent && config.expectedContentPattern) {
                                const contentValid = validateResponseContent(responseData, config.expectedContentPattern);
                                if (!contentValid) {
                                    reject(new Error(`Content validation failed: response does not match expected pattern`));
                                    return;
                                }
                                log.info('Content validation passed');
                            }
                            
                            resolve({
                                statusCode: res.statusCode,
                                responseTime: responseTime,
                                contentLength: contentLength,
                                headers: res.headers,
                                redirectCount: redirectCount,
                                contentValidated: config.validateContent
                            });
                            
                        } catch (error) {
                            reject(new Error(`Response processing error: ${error.message}`));
                        }
                    });
                });

                req.on('error', (error) => {
                    const responseTime = Date.now() - startTime;
                    log.error(`API request error after ${responseTime}ms:`, error.message);
                    
                    // Categorize different types of errors
                    let errorType = 'UNKNOWN_ERROR';
                    if (error.code === 'ECONNREFUSED') {
                        errorType = 'CONNECTION_REFUSED';
                    } else if (error.code === 'ENOTFOUND') {
                        errorType = 'DNS_RESOLUTION_FAILED';
                    } else if (error.code === 'ETIMEDOUT') {
                        errorType = 'CONNECTION_TIMEOUT';
                    } else if (error.code === 'ECONNRESET') {
                        errorType = 'CONNECTION_RESET';
                    } else if (error.code === 'CERT_HAS_EXPIRED') {
                        errorType = 'SSL_CERTIFICATE_EXPIRED';
                    } else if (error.code === 'UNABLE_TO_VERIFY_LEAF_SIGNATURE') {
                        errorType = 'SSL_CERTIFICATE_INVALID';
                    }
                    
                    reject(new Error(`${errorType}: ${error.message}`));
                });

                req.on('timeout', () => {
                    const responseTime = Date.now() - startTime;
                    log.error(`API request timeout after ${responseTime}ms`);
                    req.destroy();
                    reject(new Error(`REQUEST_TIMEOUT: Request timed out after ${config.requestTimeout}ms`));
                });

                req.end();
                
            } catch (error) {
                log.error('Error creating API request:', error.message);
                reject(new Error(`REQUEST_SETUP_ERROR: ${error.message}`));
            }
        }
        
        makeRequest(config.apiEndpoint);
    });
}

/**
 * Validates response content against expected pattern
 */
function validateResponseContent(content, pattern) {
    try {
        if (pattern.startsWith('/') && pattern.endsWith('/')) {
            // Treat as regex pattern
            const regex = new RegExp(pattern.slice(1, -1));
            return regex.test(content);
        } else {
            // Treat as simple string match
            return content.includes(pattern);
        }
    } catch (error) {
        log.error('Content validation error:', error.message);
        return false;
    }
}

/**
 * Parses custom headers from environment variable
 */
function parseCustomHeaders(headersString) {
    if (!headersString) {
        return {};
    }
    
    try {
        return JSON.parse(headersString);
    } catch (error) {
        log.warn('Failed to parse custom headers, using empty object:', error.message);
        return {};
    }
}

/**
 * Sleep utility function for retry delays
 */
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Main canary handler function with comprehensive error handling
 */
const handler = async () => {
    const executionStartTime = Date.now();
    
    return await synthetics.executeStep('canary', async function () {
        try {
            // Set synthetics configuration for detailed logging
            const syntheticsConfig = synthetics.getConfiguration();
            syntheticsConfig.setConfig({
                includeRequestHeaders: true,
                includeResponseHeaders: true,
                restrictedHeaders: ['authorization', 'x-api-key', 'cookie'],
                restrictedUrlParameters: ['token', 'key', 'password', 'auth']
            });

            logStructured('info', 'Starting API canary execution', {
                canaryName: process.env.AWS_LAMBDA_FUNCTION_NAME,
                region: process.env.AWS_REGION,
                executionId: process.env.AWS_REQUEST_ID
            });

            // Execute the API check
            const result = await apiCheck();
            const totalExecutionTime = Date.now() - executionStartTime;
            
            // Add execution metrics
            await synthetics.addUserAgentMetric('ApiExecutionTime', totalExecutionTime);
            await synthetics.addUserAgentMetric('ApiCanarySuccess', 1);
            
            logStructured('info', 'API canary completed successfully', {
                ...result,
                totalExecutionTime,
                timestamp: new Date().toISOString()
            });
            
            return {
                ...result,
                executionTime: totalExecutionTime,
                timestamp: new Date().toISOString(),
                success: true
            };
            
        } catch (error) {
            const totalExecutionTime = Date.now() - executionStartTime;
            const errorCategory = categorizeError(error);
            
            // Add failure metrics
            await synthetics.addUserAgentMetric('ApiExecutionTime', totalExecutionTime);
            await synthetics.addUserAgentMetric('ApiCanaryFailure', 1);
            await synthetics.addUserAgentMetric(`ApiExecutionError_${errorCategory}`, 1);
            
            logStructured('error', 'API canary execution failed', {
                error: error.message,
                errorCategory,
                totalExecutionTime,
                canaryName: process.env.AWS_LAMBDA_FUNCTION_NAME,
                timestamp: new Date().toISOString()
            });
            
            // Re-throw with enhanced error information
            throw new Error(`API_CANARY_EXECUTION_FAILED: ${error.message}`);
        }
    });
};

exports.handler = handler;