import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Template } from 'aws-cdk-lib/assertions';
import { CanaryConstruct } from '../lib/constructs/canary-construct';

describe('CanaryConstruct', () => {
  let app: cdk.App;
  let stack: cdk.Stack;
  let vpc: ec2.IVpc;
  let bucket: s3.Bucket;
  let role: iam.Role;
  let securityGroup: ec2.SecurityGroup;

  beforeEach(() => {
    app = new cdk.App();
    stack = new cdk.Stack(app, 'TestStack');
    
    // Create test VPC
    vpc = new ec2.Vpc(stack, 'TestVpc', {
      maxAzs: 2,
      natGateways: 1
    });
    
    // Create test bucket
    bucket = new s3.Bucket(stack, 'TestBucket');
    
    // Create test role
    role = new iam.Role(stack, 'TestRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com')
    });
    
    // Create test security group
    securityGroup = new ec2.SecurityGroup(stack, 'TestSG', {
      vpc: vpc
    });
  });

  test('creates heartbeat canary correctly', () => {
    // Create heartbeat canary
    const canaryConstruct = new CanaryConstruct(stack, 'HeartbeatCanary', {
      config: {
        name: 'test-heartbeat',
        description: 'Test heartbeat canary',
        schedule: { expression: 'rate(5 minutes)' },
        runtime: { version: 'syn-nodejs-puppeteer-6.2' },
        vpc: {
          vpcId: 'vpc-12345678',
          subnetIds: ['subnet-12345678'],
          securityGroupIds: ['sg-12345678']
        },
        environment: {
          variables: {
            TARGET_ENDPOINT: 'http://example.com',
            TIMEOUT: '30000'
          }
        },
        artifacts: {
          bucketName: bucket.bucketName,
          prefix: 'test-canary'
        },
        target: {
          name: 'test-target',
          type: 'heartbeat',
          endpoint: 'http://example.com',
          timeout: 30000
        }
      },
      executionRole: role,
      artifactsBucket: bucket,
      securityGroup: securityGroup,
      vpc: vpc
    });

    // Verify canary was created
    expect(canaryConstruct.canary).toBeDefined();
    expect(canaryConstruct.canaryName).toBe('test-heartbeat');

    // Verify CloudFormation template
    const template = Template.fromStack(stack);
    
    template.hasResourceProperties('AWS::Synthetics::Canary', {
      Name: 'test-heartbeat',
      Schedule: {
        Expression: 'rate(5 minutes)'
      },
      RuntimeVersion: 'syn-nodejs-puppeteer-6.2'
    });
  });

  test('creates API canary correctly', () => {
    // Create API canary
    const canaryConstruct = new CanaryConstruct(stack, 'ApiCanary', {
      config: {
        name: 'test-api',
        description: 'Test API canary',
        schedule: { expression: 'rate(3 minutes)' },
        runtime: { version: 'syn-nodejs-puppeteer-6.2' },
        environment: {
          variables: {
            API_ENDPOINT: 'http://api.example.com',
            EXPECTED_STATUS: '200'
          }
        },
        artifacts: {
          bucketName: bucket.bucketName,
          prefix: 'api-canary'
        },
        target: {
          name: 'api-target',
          type: 'api',
          endpoint: 'http://api.example.com',
          timeout: 10000,
          expectedStatusCodes: [200]
        }
      },
      executionRole: role,
      artifactsBucket: bucket
    });

    // Verify canary was created
    expect(canaryConstruct.canary).toBeDefined();
    expect(canaryConstruct.canaryName).toBe('test-api');

    // Verify CloudFormation template
    const template = Template.fromStack(stack);
    
    template.hasResourceProperties('AWS::Synthetics::Canary', {
      Name: 'test-api',
      Schedule: {
        Expression: 'rate(3 minutes)'
      }
    });
  });

  test('throws error for unsupported canary type', () => {
    expect(() => {
      new CanaryConstruct(stack, 'InvalidCanary', {
        config: {
          name: 'test-invalid',
          schedule: { expression: 'rate(5 minutes)' },
          runtime: { version: 'syn-nodejs-puppeteer-6.2' },
          environment: { variables: {} },
          artifacts: {
            bucketName: bucket.bucketName
          },
          target: {
            name: 'invalid-target',
            type: 'invalid' as any,
            endpoint: 'http://example.com',
            timeout: 30000
          }
        },
        executionRole: role,
        artifactsBucket: bucket
      });
    }).toThrow('Unsupported canary type: invalid');
  });
});