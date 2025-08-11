#!/usr/bin/env ts-node

/**
 * Cost Estimation Utility for CloudWatch Synthetics Monitoring
 * 
 * This script calculates estimated monthly costs for different monitoring configurations
 * and provides optimization recommendations.
 */

import * as fs from 'fs';
import * as path from 'path';

interface MonitoringConfig {
  canaryName: string;
  monitoringFrequency: string;
  additionalTargets?: Array<{
    name: string;
    type: string;
  }>;
  artifactRetentionDays: number;
  enableEscalation: boolean;
  notificationEmail: string;
  escalationEmail?: string;
  slackWebhookUrl?: string;
}

interface CostBreakdown {
  service: string;
  description: string;
  quantity: number;
  unitCost: number;
  monthlyCost: number;
}

interface CostEstimate {
  totalMonthlyCost: number;
  breakdown: CostBreakdown[];
  recommendations: string[];
  optimizationPotential: number;
}

class CostEstimator {
  // AWS pricing (as of 2024, subject to change)
  private readonly PRICING = {
    synthetics: {
      canaryRun: 0.0012, // per canary run
      freeRuns: 100 // free runs per month per canary
    },
    s3: {
      standardStorage: 0.023, // per GB per month
      requests: 0.0004 // per 1000 PUT requests
    },
    cloudwatch: {
      alarm: 0.10, // per alarm per month
      customMetric: 0.30, // per custom metric per month
      apiRequests: 0.01 // per 1000 API requests
    },
    sns: {
      email: 0.00, // first 1000 free, then $2 per 100k
      sms: 0.75, // per 100 SMS (US)
      httpNotifications: 0.60 // per 1M notifications
    },
    lambda: {
      requests: 0.0000002, // per request
      duration: 0.0000166667 // per GB-second
    }
  };

  /**
   * Parse monitoring frequency to get executions per month
   */
  private parseFrequency(frequency: string): number {
    const rateMatch = frequency.match(/rate\((\d+)\s+(minute|minutes|hour|hours|day|days)\)/);
    if (!rateMatch) {
      throw new Error(`Unsupported frequency format: ${frequency}`);
    }

    const value = parseInt(rateMatch[1]);
    const unit = rateMatch[2];

    const minutesInMonth = 30 * 24 * 60; // 43,200 minutes

    switch (unit) {
      case 'minute':
      case 'minutes':
        return minutesInMonth / value;
      case 'hour':
      case 'hours':
        return minutesInMonth / (value * 60);
      case 'day':
      case 'days':
        return minutesInMonth / (value * 60 * 24);
      default:
        throw new Error(`Unsupported time unit: ${unit}`);
    }
  }

  /**
   * Calculate Synthetics costs
   */
  private calculateSyntheticsCosts(config: MonitoringConfig): CostBreakdown[] {
    const executionsPerMonth = this.parseFrequency(config.monitoringFrequency);
    const totalCanaries = 2 + (config.additionalTargets?.length || 0); // heartbeat + api + additional
    const totalExecutions = executionsPerMonth * totalCanaries;
    
    // Free tier: 100 runs per canary per month
    const freeExecutions = totalCanaries * this.PRICING.synthetics.freeRuns;
    const billableExecutions = Math.max(0, totalExecutions - freeExecutions);
    
    const syntheticsCost = billableExecutions * this.PRICING.synthetics.canaryRun;

    return [{
      service: 'CloudWatch Synthetics',
      description: `${totalCanaries} canaries × ${Math.round(executionsPerMonth)} runs/month`,
      quantity: billableExecutions,
      unitCost: this.PRICING.synthetics.canaryRun,
      monthlyCost: syntheticsCost
    }];
  }

  /**
   * Calculate S3 storage costs
   */
  private calculateS3Costs(config: MonitoringConfig): CostBreakdown[] {
    const executionsPerMonth = this.parseFrequency(config.monitoringFrequency);
    const totalCanaries = 2 + (config.additionalTargets?.length || 0);
    const totalExecutions = executionsPerMonth * totalCanaries;
    
    // Estimate artifact size: ~50KB per execution (screenshots, logs, HAR files)
    const artifactSizePerExecution = 0.05; // MB
    const monthlyArtifactSize = totalExecutions * artifactSizePerExecution;
    
    // Calculate retention-adjusted storage
    const retentionMonths = config.artifactRetentionDays / 30;
    const averageStorageSize = (monthlyArtifactSize * retentionMonths) / 1024; // GB
    
    const storageCost = averageStorageSize * this.PRICING.s3.standardStorage;
    const requestCost = (totalExecutions / 1000) * this.PRICING.s3.requests;

    return [
      {
        service: 'S3 Storage',
        description: `${averageStorageSize.toFixed(2)} GB average storage`,
        quantity: averageStorageSize,
        unitCost: this.PRICING.s3.standardStorage,
        monthlyCost: storageCost
      },
      {
        service: 'S3 Requests',
        description: `${totalExecutions} PUT requests/month`,
        quantity: totalExecutions / 1000,
        unitCost: this.PRICING.s3.requests,
        monthlyCost: requestCost
      }
    ];
  }

  /**
   * Calculate CloudWatch costs
   */
  private calculateCloudWatchCosts(config: MonitoringConfig): CostBreakdown[] {
    const totalCanaries = 2 + (config.additionalTargets?.length || 0);
    
    // Standard alarms per canary: failure, duration, success rate, high latency
    const standardAlarmsPerCanary = 4;
    // Escalation alarms if enabled
    const escalationAlarmsPerCanary = config.enableEscalation ? 1 : 0;
    // Composite alarms per canary
    const compositeAlarmsPerCanary = 1;
    
    const totalAlarms = totalCanaries * (standardAlarmsPerCanary + escalationAlarmsPerCanary + compositeAlarmsPerCanary);
    
    // Custom metrics: each canary publishes ~5 custom metrics
    const customMetricsPerCanary = 5;
    const totalCustomMetrics = totalCanaries * customMetricsPerCanary;
    
    const alarmCost = totalAlarms * this.PRICING.cloudwatch.alarm;
    const metricCost = totalCustomMetrics * this.PRICING.cloudwatch.customMetric;

    return [
      {
        service: 'CloudWatch Alarms',
        description: `${totalAlarms} alarms`,
        quantity: totalAlarms,
        unitCost: this.PRICING.cloudwatch.alarm,
        monthlyCost: alarmCost
      },
      {
        service: 'CloudWatch Custom Metrics',
        description: `${totalCustomMetrics} custom metrics`,
        quantity: totalCustomMetrics,
        unitCost: this.PRICING.cloudwatch.customMetric,
        monthlyCost: metricCost
      }
    ];
  }

  /**
   * Calculate SNS notification costs
   */
  private calculateSNSCosts(config: MonitoringConfig): CostBreakdown[] {
    const costs: CostBreakdown[] = [];
    
    // Estimate notifications per month based on expected failure rate
    const executionsPerMonth = this.parseFrequency(config.monitoringFrequency);
    const totalCanaries = 2 + (config.additionalTargets?.length || 0);
    const totalExecutions = executionsPerMonth * totalCanaries;
    
    // Assume 2% failure rate for cost estimation
    const failureRate = 0.02;
    const estimatedFailures = totalExecutions * failureRate;
    
    // Email notifications (free for first 1000)
    const emailNotifications = estimatedFailures * 2; // failure + recovery
    const billableEmails = Math.max(0, emailNotifications - 1000);
    const emailCost = (billableEmails / 100000) * 2; // $2 per 100k after first 1000
    
    if (emailNotifications > 0) {
      costs.push({
        service: 'SNS Email',
        description: `${Math.round(emailNotifications)} email notifications/month`,
        quantity: billableEmails,
        unitCost: 2 / 100000,
        monthlyCost: emailCost
      });
    }
    
    // Slack notifications (HTTP notifications)
    if (config.slackWebhookUrl) {
      const slackNotifications = estimatedFailures * 2;
      const slackCost = (slackNotifications / 1000000) * this.PRICING.sns.httpNotifications;
      
      costs.push({
        service: 'SNS HTTP (Slack)',
        description: `${Math.round(slackNotifications)} Slack notifications/month`,
        quantity: slackNotifications / 1000000,
        unitCost: this.PRICING.sns.httpNotifications,
        monthlyCost: slackCost
      });
    }

    return costs;
  }

  /**
   * Calculate Lambda costs for Slack integration
   */
  private calculateLambdaCosts(config: MonitoringConfig): CostBreakdown[] {
    if (!config.slackWebhookUrl) {
      return [];
    }

    const executionsPerMonth = this.parseFrequency(config.monitoringFrequency);
    const totalCanaries = 2 + (config.additionalTargets?.length || 0);
    const totalExecutions = executionsPerMonth * totalCanaries;
    
    // Estimate Lambda invocations (2% failure rate)
    const failureRate = 0.02;
    const lambdaInvocations = totalExecutions * failureRate * 2; // failure + recovery
    
    // Lambda pricing (128MB, ~200ms execution time)
    const memoryGB = 0.125;
    const executionTimeSeconds = 0.2;
    const gbSeconds = lambdaInvocations * memoryGB * executionTimeSeconds;
    
    const requestCost = lambdaInvocations * this.PRICING.lambda.requests;
    const durationCost = gbSeconds * this.PRICING.lambda.duration;
    const totalLambdaCost = requestCost + durationCost;

    return [{
      service: 'Lambda (Slack)',
      description: `${Math.round(lambdaInvocations)} invocations/month`,
      quantity: lambdaInvocations,
      unitCost: (requestCost + durationCost) / lambdaInvocations,
      monthlyCost: totalLambdaCost
    }];
  }

  /**
   * Generate cost optimization recommendations
   */
  private generateRecommendations(config: MonitoringConfig, totalCost: number): string[] {
    const recommendations: string[] = [];
    const executionsPerMonth = this.parseFrequency(config.monitoringFrequency);

    // Frequency optimization
    if (executionsPerMonth > 8640) { // More than every 5 minutes
      recommendations.push(
        `Consider reducing monitoring frequency from ${config.monitoringFrequency} to save ~${(totalCost * 0.3).toFixed(2)}/month`
      );
    }

    // Retention optimization
    if (config.artifactRetentionDays > 30) {
      recommendations.push(
        `Reduce artifact retention from ${config.artifactRetentionDays} to 30 days to save ~${(totalCost * 0.1).toFixed(2)}/month`
      );
    }

    // Alarm optimization
    if (config.enableEscalation) {
      recommendations.push(
        'Consider using composite alarms instead of individual escalation alarms to reduce alarm costs'
      );
    }

    // Regional optimization
    recommendations.push(
      'Deploy in us-east-1 region for lowest CloudWatch Synthetics costs'
    );

    // Monitoring strategy
    if ((config.additionalTargets?.length || 0) > 3) {
      recommendations.push(
        'Consider consolidating similar monitoring targets to reduce canary count'
      );
    }

    return recommendations;
  }

  /**
   * Estimate total costs for a configuration
   */
  public estimateCosts(config: MonitoringConfig): CostEstimate {
    const breakdown: CostBreakdown[] = [
      ...this.calculateSyntheticsCosts(config),
      ...this.calculateS3Costs(config),
      ...this.calculateCloudWatchCosts(config),
      ...this.calculateSNSCosts(config),
      ...this.calculateLambdaCosts(config)
    ];

    const totalMonthlyCost = breakdown.reduce((sum, item) => sum + item.monthlyCost, 0);
    const recommendations = this.generateRecommendations(config, totalMonthlyCost);
    
    // Calculate optimization potential (rough estimate)
    const optimizationPotential = totalMonthlyCost * 0.25; // Assume 25% potential savings

    return {
      totalMonthlyCost,
      breakdown,
      recommendations,
      optimizationPotential
    };
  }
}

/**
 * Format cost estimate for display
 */
function formatCostEstimate(estimate: CostEstimate): string {
  let output = '\n=== CloudWatch Synthetics Cost Estimate ===\n\n';
  
  output += 'Cost Breakdown:\n';
  output += '-'.repeat(80) + '\n';
  output += sprintf('%-25s %-35s %10s %10s %12s\n', 
    'Service', 'Description', 'Quantity', 'Unit Cost', 'Monthly Cost');
  output += '-'.repeat(80) + '\n';
  
  for (const item of estimate.breakdown) {
    output += sprintf('%-25s %-35s %10.2f $%9.4f $%11.2f\n',
      item.service,
      item.description.substring(0, 35),
      item.quantity,
      item.unitCost,
      item.monthlyCost
    );
  }
  
  output += '-'.repeat(80) + '\n';
  output += sprintf('%-71s $%11.2f\n', 'TOTAL ESTIMATED MONTHLY COST:', estimate.totalMonthlyCost);
  output += '-'.repeat(80) + '\n\n';
  
  if (estimate.recommendations.length > 0) {
    output += 'Cost Optimization Recommendations:\n';
    output += '-'.repeat(50) + '\n';
    for (let i = 0; i < estimate.recommendations.length; i++) {
      output += `${i + 1}. ${estimate.recommendations[i]}\n`;
    }
    output += `\nPotential Monthly Savings: $${estimate.optimizationPotential.toFixed(2)}\n\n`;
  }
  
  return output;
}

/**
 * Simple sprintf implementation
 */
function sprintf(format: string, ...args: any[]): string {
  let i = 0;
  return format.replace(/%[sd%]/g, (match) => {
    if (match === '%%') return '%';
    if (i >= args.length) return match;
    const arg = args[i++];
    return match === '%s' ? String(arg) : String(Number(arg));
  }).replace(/%-?(\d+)s/g, (match, width) => {
    if (i >= args.length) return match;
    const arg = String(args[i++]);
    const w = parseInt(width);
    return match.startsWith('%-') ? arg.padEnd(w) : arg.padStart(w);
  }).replace(/\$%(\d+)\.(\d+)f/g, (match, width, precision) => {
    if (i >= args.length) return match;
    const arg = Number(args[i++]);
    return '$' + arg.toFixed(parseInt(precision)).padStart(parseInt(width) - 1);
  }).replace(/%(\d+)\.(\d+)f/g, (match, width, precision) => {
    if (i >= args.length) return match;
    const arg = Number(args[i++]);
    return arg.toFixed(parseInt(precision)).padStart(parseInt(width));
  });
}

/**
 * Main function
 */
async function main() {
  const args = process.argv.slice(2);
  
  if (args.length === 0) {
    console.log('Usage: ts-node cost-estimate.ts <config-file>');
    console.log('Example: ts-node cost-estimate.ts ../examples/dev-config.json');
    process.exit(1);
  }
  
  const configFile = args[0];
  
  if (!fs.existsSync(configFile)) {
    console.error(`Configuration file not found: ${configFile}`);
    process.exit(1);
  }
  
  try {
    const configContent = fs.readFileSync(configFile, 'utf8');
    const config: MonitoringConfig = JSON.parse(configContent);
    
    const estimator = new CostEstimator();
    const estimate = estimator.estimateCosts(config);
    
    console.log(formatCostEstimate(estimate));
    
    // Also save to file
    const outputFile = path.join(path.dirname(configFile), `cost-estimate-${config.canaryName}.txt`);
    fs.writeFileSync(outputFile, formatCostEstimate(estimate));
    console.log(`Cost estimate saved to: ${outputFile}`);
    
  } catch (error) {
    console.error('Error processing configuration:', error);
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main().catch(console.error);
}

export { CostEstimator, CostEstimate, CostBreakdown };