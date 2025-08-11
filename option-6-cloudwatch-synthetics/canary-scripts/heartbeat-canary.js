const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');
const https = require('https');
const http = require('http');
const { URL } = require('url');

/**
 * Heartbeat Canary Script for On-Premises Monitoring
 * 
 * This canary performs basic connectivity testing to on-premises endpoints
 * with enhanced error handling, detailed logging, and comprehensive metrics.
 * 
 * Error handling strategy:
 * - Simple retry logic (no exponential backoff)
 * - Detailed error categorization and logging
 * - CloudWatch alarms handle sophisticated alerting
 * - Custom metrics for monitoring insights
 */

// Error categories for detailed monitoring
const ERROR_CATEGORIES = {
    NETWORK: 'NETWORK_ERROR',
    DNS: 'DNS_ERROR', 
    TIMEOUT: 'TIMEOUT_ERROR',
    HTTP: 'HTTP_ERROR',
    CONFIG: 'CONFIG_ERROR',
    UNKNOWN: 'UNKNOWN_ERROR'
};

// Performance thresholds for categorization
const PERFORMANCE_THRESHOLDS = {
    FAST: 1000,      // < 1s
    NORMAL: 3000,    // 1-3s
    SLOW: 10000,     // 3-10s
    VERY_SLOW: 30000 // > 10s
};

/**
 * Enhanced logging utility with structured output
 */
function logStructured(level, message, data = {}) {
    const logEntry = {
        timestamp: new Date().toISOString(),
        level: level.toUpperCase(),
        message,
        canaryName: process.env.AWS_LAMBDA_FUNCTION_NAME || 'heartbeat-canary',
        ...data
    };
    
    log[level](JSON.stringify(logEntry));
}

/**
 * Categorize error based on error code and message
 */
function categorizeError(error) {
    if (!error || !error.code) {
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
    
    if (error.message && error.message.includes('status code')) {
        return ERROR_CATEGORIES.HTTP;
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

const heartbeatCheck = async function () {
    // Configuration from environment variables with validation
    const config = {
        endpoint: process.env.TARGET_ENDPOINT || 'http://localhost:8080',
        timeout: Math.max(1000, parseInt(process.env.TIMEOUT) || 30000),
        retries: Math.max(1, Math.min(5, parseInt(process.env.RETRIES) || 3)),
        retryDelay: Math.max(500, parseInt(process.env.RETRY_DELAY) || 1000),
        expectedStatusCodes: process.env.EXPECTED_STATUS_CODES ? 
            process.env.EXPECTED_STATUS_CODES.split(',').map(code => parseInt(code.trim())) : 
            [200, 201, 202, 204],
        userAgent: process.env.USER_AGENT || 'AWS-Synthetics-Heartbeat-Canary/1.0'
    };

    // Validate configuration
    try {
        new URL(config.endpoint);
    } catch (error) {
        logStructured('error', 'Invalid endpoint URL configuration', { 
            endpoint: config.endpoint, 
            error: error.message 
        });
        throw new Error(`CONFIG_ERROR: Invalid endpoint URL: ${config.endpoint}`);
    }

    logStructured('info', 'Starting heartbeat check', { 
        config: {
            ...config,
            // Don't log sensitive headers
            userAgent: config.userAgent.substring(0, 50) + '...'
        }
    });

    return await synthetics.executeStep('heartbeat-connectivity-test', async function() {
        let lastError = null;
        let errorCategory = ERROR_CATEGORIES.UNKNOWN;
        const attemptResults = [];
        
        for (let attempt = 1; attempt <= config.retries; attempt++) {
            const attemptStartTime = Date.now();
            
            try {
                logStructured('info', 'Starting connectivity attempt', {
                    attempt,
                    totalAttempts: config.retries,
                    endpoint: config.endpoint,
                    timeout: config.timeout
                });
                
                const result = await performConnectivityTest(config);
                const performanceCategory = categorizePerformance(result.responseTime);
                
                // Log successful connection with detailed metrics
                logStructured('info', 'Heartbeat check successful', {
                    attempt,
                    endpoint: config.endpoint,
                    responseTime: result.responseTime,
                    statusCode: result.statusCode,
                    performanceCategory,
                    headers: Object.keys(result.headers || {}).length
                });

                // Add comprehensive custom metrics
                await synthetics.addUserAgentMetric('HeartbeatSuccess', 1);
                await synthetics.addUserAgentMetric('ResponseTime', result.responseTime);
                await synthetics.addUserAgentMetric('AttemptsRequired', attempt);
                await synthetics.addUserAgentMetric(`Performance_${performanceCategory}`, 1);
                await synthetics.addUserAgentMetric('StatusCode_' + result.statusCode, 1);

                // Add success result to attempts log
                attemptResults.push({
                    attempt,
                    success: true,
                    responseTime: result.responseTime,
                    statusCode: result.statusCode,
                    performanceCategory
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
                
                logStructured('warn', 'Connectivity attempt failed', {
                    attempt,
                    totalAttempts: config.retries,
                    error: error.message,
                    errorCategory,
                    attemptDuration,
                    willRetry: attempt < config.retries
                });
                
                // Add failure metrics with categorization
                await synthetics.addUserAgentMetric('HeartbeatFailure', 1);
                await synthetics.addUserAgentMetric(`Error_${errorCategory}`, 1);
                
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
        logStructured('error', 'Heartbeat check failed after all retries', {
            totalAttempts: config.retries,
            lastError: lastError.message,
            errorCategory,
            attemptResults,
            endpoint: config.endpoint
        });
        
        // Add final failure metrics
        await synthetics.addUserAgentMetric('HeartbeatTotalFailure', 1);
        await synthetics.addUserAgentMetric('AttemptsRequired', config.retries);
        await synthetics.addUserAgentMetric(`FinalError_${errorCategory}`, 1);
        
        // Create detailed error message
        const errorMessage = `${errorCategory}: Heartbeat check failed after ${config.retries} attempts. Last error: ${lastError.message}`;
        throw new Error(errorMessage);
    });
};

/**
 * Performs the actual connectivity test to the target endpoint with enhanced error handling
 */
async function performConnectivityTest(config) {
    return new Promise((resolve, reject) => {
        const startTime = Date.now();
        let requestCompleted = false;
        
        try {
            const url = new URL(config.endpoint);
            const isHttps = url.protocol === 'https:';
            const client = isHttps ? https : http;
            
            const requestOptions = {
                hostname: url.hostname,
                port: url.port || (isHttps ? 443 : 80),
                path: url.pathname + url.search,
                method: 'GET',
                timeout: config.timeout,
                headers: {
                    'User-Agent': config.userAgent,
                    'Accept': '*/*',
                    'Connection': 'close',
                    'Cache-Control': 'no-cache'
                }
            };

            logStructured('debug', 'Making HTTP request', {
                hostname: requestOptions.hostname,
                port: requestOptions.port,
                path: requestOptions.path,
                isHttps,
                timeout: config.timeout
            });

            const req = client.request(requestOptions, (res) => {
                if (requestCompleted) return;
                requestCompleted = true;
                
                const responseTime = Date.now() - startTime;
                
                logStructured('debug', 'Received HTTP response', {
                    statusCode: res.statusCode,
                    responseTime,
                    contentLength: res.headers['content-length'],
                    contentType: res.headers['content-type']
                });
                
                // Check if status code is expected
                if (config.expectedStatusCodes.includes(res.statusCode)) {
                    // Consume response data to free up memory and get content length
                    let contentLength = 0;
                    res.on('data', (chunk) => {
                        contentLength += chunk.length;
                    });
                    
                    res.on('end', () => {
                        resolve({
                            statusCode: res.statusCode,
                            responseTime: responseTime,
                            headers: res.headers,
                            contentLength,
                            protocol: isHttps ? 'https' : 'http'
                        });
                    });
                    
                    res.on('error', (error) => {
                        if (!requestCompleted) {
                            requestCompleted = true;
                            logStructured('error', 'Response stream error', { error: error.message });
                            reject(new Error(`RESPONSE_ERROR: ${error.message}`));
                        }
                    });
                } else {
                    // Consume response data even for unexpected status codes
                    res.on('data', () => {});
                    res.on('end', () => {});
                    
                    reject(new Error(`HTTP_ERROR: Unexpected status code ${res.statusCode}. Expected one of: ${config.expectedStatusCodes.join(', ')}`));
                }
            });

            req.on('error', (error) => {
                if (requestCompleted) return;
                requestCompleted = true;
                
                const responseTime = Date.now() - startTime;
                
                logStructured('error', 'HTTP request error', {
                    error: error.message,
                    errorCode: error.code,
                    responseTime,
                    hostname: requestOptions.hostname,
                    port: requestOptions.port
                });
                
                // Enhanced error categorization with more specific error types
                let errorMessage = error.message;
                if (error.code === 'ECONNREFUSED') {
                    errorMessage = `Connection refused to ${requestOptions.hostname}:${requestOptions.port}`;
                } else if (error.code === 'ENOTFOUND') {
                    errorMessage = `DNS resolution failed for ${requestOptions.hostname}`;
                } else if (error.code === 'ETIMEDOUT') {
                    errorMessage = `Connection timeout to ${requestOptions.hostname}:${requestOptions.port}`;
                } else if (error.code === 'ECONNRESET') {
                    errorMessage = `Connection reset by ${requestOptions.hostname}:${requestOptions.port}`;
                } else if (error.code === 'EHOSTUNREACH') {
                    errorMessage = `Host unreachable: ${requestOptions.hostname}`;
                } else if (error.code === 'ENETUNREACH') {
                    errorMessage = `Network unreachable to ${requestOptions.hostname}`;
                }
                
                reject(new Error(errorMessage));
            });

            req.on('timeout', () => {
                if (requestCompleted) return;
                requestCompleted = true;
                
                const responseTime = Date.now() - startTime;
                
                logStructured('error', 'HTTP request timeout', {
                    timeout: config.timeout,
                    responseTime,
                    hostname: requestOptions.hostname,
                    port: requestOptions.port
                });
                
                req.destroy();
                reject(new Error(`TIMEOUT_ERROR: Request timed out after ${config.timeout}ms to ${requestOptions.hostname}:${requestOptions.port}`));
            });

            // Set a safety timeout to prevent hanging requests
            const safetyTimeout = setTimeout(() => {
                if (!requestCompleted) {
                    requestCompleted = true;
                    req.destroy();
                    reject(new Error(`SAFETY_TIMEOUT: Request exceeded safety timeout of ${config.timeout + 5000}ms`));
                }
            }, config.timeout + 5000);

            req.on('close', () => {
                clearTimeout(safetyTimeout);
            });

            req.end();
            
        } catch (error) {
            if (requestCompleted) return;
            requestCompleted = true;
            
            logStructured('error', 'Request setup error', {
                error: error.message,
                endpoint: config.endpoint
            });
            
            reject(new Error(`CONFIG_ERROR: Failed to setup request - ${error.message}`));
        }
    });
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
                restrictedHeaders: ['authorization', 'x-api-key'],
                restrictedUrlParameters: ['token', 'key', 'password']
            });

            logStructured('info', 'Starting canary execution', {
                canaryName: process.env.AWS_LAMBDA_FUNCTION_NAME,
                region: process.env.AWS_REGION,
                executionId: process.env.AWS_REQUEST_ID
            });

            // Execute the heartbeat check
            const result = await heartbeatCheck();
            const totalExecutionTime = Date.now() - executionStartTime;
            
            // Add execution metrics
            await synthetics.addUserAgentMetric('ExecutionTime', totalExecutionTime);
            await synthetics.addUserAgentMetric('CanarySuccess', 1);
            
            logStructured('info', 'Heartbeat canary completed successfully', {
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
            await synthetics.addUserAgentMetric('ExecutionTime', totalExecutionTime);
            await synthetics.addUserAgentMetric('CanaryFailure', 1);
            await synthetics.addUserAgentMetric(`ExecutionError_${errorCategory}`, 1);
            
            logStructured('error', 'Heartbeat canary execution failed', {
                error: error.message,
                errorCategory,
                totalExecutionTime,
                canaryName: process.env.AWS_LAMBDA_FUNCTION_NAME,
                timestamp: new Date().toISOString()
            });
            
            // Re-throw with enhanced error information
            throw new Error(`CANARY_EXECUTION_FAILED: ${error.message}`);
        }
    });
};

exports.handler = handler;