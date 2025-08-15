/**
 * Local test script for heartbeat canary
 * This script mocks the AWS Synthetics environment for local testing
 */

// Mock AWS Synthetics modules for local testing
const mockSynthetics = {
    executeStep: async (stepName, stepFunction) => {
        console.log(`Executing step: ${stepName}`);
        return await stepFunction();
    },
    addUserAgentMetric: async (metricName, value) => {
        console.log(`Metric: ${metricName} = ${value}`);
    },
    getConfiguration: () => ({
        setConfig: (config) => {
            console.log('Synthetics config set:', config);
        }
    })
};

const mockLogger = {
    info: (...args) => console.log('[INFO]', ...args),
    warn: (...args) => console.warn('[WARN]', ...args),
    error: (...args) => console.error('[ERROR]', ...args)
};

// Mock the modules using Module._cache
const Module = require('module');
const originalRequire = Module.prototype.require;

Module.prototype.require = function(id) {
    if (id === 'Synthetics') return mockSynthetics;
    if (id === 'SyntheticsLogger') return mockLogger;
    return originalRequire.apply(this, arguments);
};

// Set test environment variables
process.env.TARGET_ENDPOINT = 'http://httpbin.org/status/200';
process.env.TIMEOUT = '10000';
process.env.RETRIES = '2';
process.env.EXPECTED_STATUS_CODES = '200';

// Import and run the canary
const { handler } = require('./heartbeat-canary');

async function runTest() {
    console.log('Starting heartbeat canary test...');
    console.log('Environment variables:');
    console.log('- TARGET_ENDPOINT:', process.env.TARGET_ENDPOINT);
    console.log('- TIMEOUT:', process.env.TIMEOUT);
    console.log('- RETRIES:', process.env.RETRIES);
    console.log('- EXPECTED_STATUS_CODES:', process.env.EXPECTED_STATUS_CODES);
    console.log('');

    try {
        const result = await handler();
        console.log('\n✅ Test completed successfully!');
        console.log('Result:', result);
    } catch (error) {
        console.error('\n❌ Test failed!');
        console.error('Error:', error.message);
        process.exit(1);
    }
}

// Run the test
runTest();