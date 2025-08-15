/**
 * Local test script for heartbeat canary failure scenarios
 * This script tests error handling and retry logic
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

// Set test environment variables for failure scenario
process.env.TARGET_ENDPOINT = 'http://non-existent-host.invalid:8080';
process.env.TIMEOUT = '5000';
process.env.RETRIES = '2';
process.env.RETRY_DELAY = '500';
process.env.EXPECTED_STATUS_CODES = '200';

// Import and run the canary
const { handler } = require('./heartbeat-canary');

async function runFailureTest() {
    console.log('Starting heartbeat canary failure test...');
    console.log('Environment variables:');
    console.log('- TARGET_ENDPOINT:', process.env.TARGET_ENDPOINT);
    console.log('- TIMEOUT:', process.env.TIMEOUT);
    console.log('- RETRIES:', process.env.RETRIES);
    console.log('- RETRY_DELAY:', process.env.RETRY_DELAY);
    console.log('');

    try {
        const result = await handler();
        console.log('\n❌ Test should have failed but succeeded!');
        console.log('Result:', result);
        process.exit(1);
    } catch (error) {
        console.log('\n✅ Test failed as expected!');
        console.log('Error:', error.message);
        console.log('\nThis demonstrates proper error handling and retry logic.');
    }
}

// Run the test
runFailureTest();