#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { CanaryInfrastructureStack } from '../lib/canary-infrastructure-stack';

const app = new cdk.App();

// Get configuration from context or environment variables
const config = {
  canaryName: app.node.tryGetContext('canaryName') || process.env.CANARY_NAME || 'on-premises-monitor',
  monitoringFrequency: app.node.tryGetContext('monitoringFrequency') || process.env.MONITORING_FREQUENCY || 'rate(5 minutes)',
  vpcId: app.node.tryGetContext('vpcId') || process.env.VPC_ID,
  subnetIds: app.node.tryGetContext('subnetIds') || process.env.SUBNET_IDS?.split(',') || [],
  onPremisesCIDR: app.node.tryGetContext('onPremisesCIDR') || process.env.ON_PREMISES_CIDR || '10.0.0.0/8',
  targetEndpoint: app.node.tryGetContext('targetEndpoint') || process.env.TARGET_ENDPOINT || '10.1.1.100',
  targetPort: parseInt(app.node.tryGetContext('targetPort') || process.env.TARGET_PORT || '80'),
  notificationEmail: app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL,
  escalationEmail: app.node.tryGetContext('escalationEmail') || process.env.ESCALATION_EMAIL,
  slackWebhookUrl: app.node.tryGetContext('slackWebhookUrl') || process.env.SLACK_WEBHOOK_URL,
  alarmThreshold: parseInt(app.node.tryGetContext('alarmThreshold') || process.env.ALARM_THRESHOLD || '2'),
  escalationThreshold: parseInt(app.node.tryGetContext('escalationThreshold') || process.env.ESCALATION_THRESHOLD || '5'),
  highLatencyThreshold: parseInt(app.node.tryGetContext('highLatencyThreshold') || process.env.HIGH_LATENCY_THRESHOLD || '5000'),
  enableEscalation: (app.node.tryGetContext('enableEscalation') || process.env.ENABLE_ESCALATION || 'true') === 'true',
  artifactRetentionDays: parseInt(app.node.tryGetContext('artifactRetentionDays') || process.env.ARTIFACT_RETENTION_DAYS || '30')
};

// Validate required configuration
if (!config.vpcId) {
  throw new Error('VPC ID is required. Set via context or VPC_ID environment variable.');
}
if (config.subnetIds.length === 0) {
  throw new Error('Subnet IDs are required. Set via context or SUBNET_IDS environment variable (comma-separated).');
}
if (!config.notificationEmail) {
  throw new Error('Notification email is required. Set via context or NOTIFICATION_EMAIL environment variable.');
}

new CanaryInfrastructureStack(app, 'CanaryInfrastructureStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  config
});