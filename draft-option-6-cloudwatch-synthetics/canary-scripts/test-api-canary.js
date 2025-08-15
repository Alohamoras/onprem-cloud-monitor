/**
 * Local test script for API canary
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

// Test scenarios
const testScenarios = [
    {
        name: 'Basic S3 Endpoint Test',
        env: {
            API_ENDPOINT: 'https://www.google.com',
            EXPECTED_STATUS: '200',
            REQUEST_TIMEOUT: '10000',
            RETRIES: '2'
        }
    },
    {
        name: 'S3 Endpoint with Custom Headers',
        env: {
            API_ENDPOINT: 'http://httpbin.org/headers',
            EXPECTED_STATUS: '200',
            REQUEST_TIMEOUT: '10000',
            RETRIES: '2',
            CUSTOM_HEADERS: '{"X-Custom-Header": "test-value", "Authorization": "Bearer test-token"}'
        }
    },
    {
        name: 'S3 Endpoint with Content Validation',
        env: {
            API_ENDPOINT: 'http://httpbin.org/json',
            EXPECTED_STATUS: '200',
            REQUEST_TIMEOUT: '10000',
            RETRIES: '2',
            VALIDATE_CONTENT: 'true',
            EXPECTED_CONTENT_PATTERN: 'slideshow'
        }
    },
    {
        name: 'S3 Endpoint with Redirect Following',
        env: {
            API_ENDPOINT: 'http://httpbin.org/redirect/1',
            EXPECTED_STATUS: '200',
            REQUEST_TIMEOUT: '10000',
            RETRIES: '2',
            FOLLOW_REDIRECTS: 'true',
            MAX_REDIRECTS: '5'
        }
    },
    {
        name: 'Snowball S3 Endpoint Simulation (Port 8080)',
        env: {
            API_ENDPOINT: 'http://httpbin.org/get',
            EXPECTED_STATUS: '200',
            REQUEST_TIMEOUT: '15000',
            RETRIES: '3',
            CUSTOM_HEADERS: '{"Host": "snowball-s3-endpoint:8080"}',
            USER_AGENT: 'Snowball-S3-Monitor/1.0'
        }
    }
];

async function runTestScenario(scenario) {
    console.log(`\n${'='.repeat(60)}`);
    console.log(`Running test scenario: ${scenario.name}`);
    console.log(`${'='.repeat(60)}`);
    
    // Set environment variables for this scenario
    Object.keys(scenario.env).forEach(key => {
        process.env[key] = scenario.env[key];
    });
    
    console.log('Environment variables:');
    Object.keys(scenario.env).forEach(key => {
        console.log(`- ${key}: ${scenario.env[key]}`);
    });
    console.log('');

    try {
        // Import the canary (fresh require for each test)
        delete require.cache[require.resolve('./api-canary')];
        const { handler } = require('./api-canary');
        
        const result = await handler();
        console.log('\n✅ Test scenario completed successfully!');
        console.log('Result:', JSON.stringify(result, null, 2));
        return true;
    } catch (error) {
        console.error('\n❌ Test scenario failed!');
        console.error('Error:', error.message);
        return false;
    }
}

async function runAllTests() {
    console.log('Starting API canary test suite...');
    
    let passedTests = 0;
    let totalTests = testScenarios.length;
    
    for (const scenario of testScenarios) {
        const passed = await runTestScenario(scenario);
        if (passed) {
            passedTests++;
        }
        
        // Clean up environment variables
        Object.keys(scenario.env).forEach(key => {
            delete process.env[key];
        });
    }
    
    console.log(`\n${'='.repeat(60)}`);
    console.log(`Test Results: ${passedTests}/${totalTests} scenarios passed`);
    console.log(`${'='.repeat(60)}`);
    
    if (passedTests === totalTests) {
        console.log('🎉 All tests passed!');
        process.exit(0);
    } else {
        console.log('❌ Some tests failed!');
        process.exit(1);
    }
}

// Check if a specific test scenario should be run
const scenarioName = process.argv[2];
if (scenarioName) {
    const scenario = testScenarios.find(s => s.name.toLowerCase().includes(scenarioName.toLowerCase()));
    if (scenario) {
        runTestScenario(scenario).then(passed => {
            process.exit(passed ? 0 : 1);
        });
    } else {
        console.error(`Test scenario "${scenarioName}" not found.`);
        console.log('Available scenarios:');
        testScenarios.forEach(s => console.log(`- ${s.name}`));
        process.exit(1);
    }
} else {
    // Run all tests
    runAllTests();
}