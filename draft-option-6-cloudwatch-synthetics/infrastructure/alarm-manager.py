#!/usr/bin/env python3
"""
CloudWatch Synthetics Alarm Management Utility

This script provides utilities for managing CloudWatch alarms for Synthetics canaries,
including alarm creation, configuration validation, and cost estimation.
"""

import json
import boto3
import argparse
import sys
from typing import Dict, List, Optional
from datetime import datetime, timedelta


class AlarmManager:
    """Manages CloudWatch alarms for Synthetics canaries"""
    
    def __init__(self, region: str = 'us-east-1'):
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        self.synthetics = boto3.client('synthetics', region_name=region)
        self.sns = boto3.client('sns', region_name=region)
        self.region = region
        
    def load_alarm_config(self, config_file: str = 'alarm-config.json') -> Dict:
        """Load alarm configuration from JSON file"""
        try:
            with open(config_file, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"Error: Configuration file {config_file} not found")
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in configuration file: {e}")
            sys.exit(1)
    
    def list_canaries(self) -> List[Dict]:
        """List all Synthetics canaries"""
        try:
            response = self.synthetics.describe_canaries()
            return response.get('Canaries', [])
        except Exception as e:
            print(f"Error listing canaries: {e}")
            return []
    
    def create_alarm(self, alarm_config: Dict, canary_name: str, alarm_type: str, 
                    notification_topic_arn: str, **kwargs) -> bool:
        """Create a CloudWatch alarm for a canary"""
        
        alarm_name = f"{canary_name}-{alarm_type}"
        
        # Replace configurable values
        threshold = alarm_config['threshold']
        if threshold == 'configurable':
            threshold = kwargs.get('threshold', 5000)
        
        evaluation_periods = alarm_config['evaluationPeriods']
        if evaluation_periods == 'configurable':
            evaluation_periods = kwargs.get('alarmThreshold', 2)
        elif evaluation_periods == 'escalationThreshold':
            evaluation_periods = kwargs.get('escalationThreshold', 5)
        
        try:
            self.cloudwatch.put_metric_alarm(
                AlarmName=alarm_name,
                AlarmDescription=f"{alarm_config['description']} for {canary_name}",
                MetricName=alarm_config['metricName'],
                Namespace=alarm_config['namespace'],
                Statistic=alarm_config['statistic'],
                Dimensions=[
                    {
                        'Name': 'CanaryName',
                        'Value': canary_name
                    }
                ],
                Period=alarm_config['period'],
                EvaluationPeriods=evaluation_periods,
                Threshold=threshold,
                ComparisonOperator=alarm_config['comparisonOperator'],
                TreatMissingData=alarm_config['treatMissingData'],
                AlarmActions=[notification_topic_arn],
                OKActions=[notification_topic_arn],
                Tags=[
                    {'Key': 'AlarmType', 'Value': alarm_type},
                    {'Key': 'CanaryName', 'Value': canary_name},
                    {'Key': 'ManagedBy', 'Value': 'AlarmManager'}
                ]
            )
            print(f"✓ Created alarm: {alarm_name}")
            return True
        except Exception as e:
            print(f"✗ Failed to create alarm {alarm_name}: {e}")
            return False
    
    def create_composite_alarm(self, canary_names: List[str], 
                             notification_topic_arn: str) -> bool:
        """Create a composite alarm for overall health"""
        
        # Build alarm rule for critical alarms
        alarm_rules = []
        for canary_name in canary_names:
            alarm_rules.extend([
                f'ALARM("{canary_name}-failure")',
                f'ALARM("{canary_name}-duration")'
            ])
        
        alarm_rule = ' OR '.join(alarm_rules)
        
        try:
            self.cloudwatch.put_composite_alarm(
                AlarmName='overall-canary-health',
                AlarmDescription='Composite alarm for overall canary health status',
                AlarmRule=alarm_rule,
                AlarmActions=[notification_topic_arn],
                OKActions=[notification_topic_arn],
                Tags=[
                    {'Key': 'AlarmType', 'Value': 'Composite'},
                    {'Key': 'ManagedBy', 'Value': 'AlarmManager'}
                ]
            )
            print("✓ Created composite alarm: overall-canary-health")
            return True
        except Exception as e:
            print(f"✗ Failed to create composite alarm: {e}")
            return False
    
    def validate_configuration(self, config: Dict) -> bool:
        """Validate alarm configuration"""
        required_sections = ['alarmConfigurations', 'notificationChannels', 'escalationRules']
        
        for section in required_sections:
            if section not in config:
                print(f"✗ Missing required section: {section}")
                return False
        
        # Validate alarm configurations
        for alarm_type, alarm_config in config['alarmConfigurations'].items():
            required_fields = ['metricName', 'namespace', 'statistic', 'threshold', 'comparisonOperator']
            for field in required_fields:
                if field not in alarm_config:
                    print(f"✗ Missing field '{field}' in alarm configuration '{alarm_type}'")
                    return False
        
        print("✓ Configuration validation passed")
        return True
    
    def estimate_costs(self, config: Dict, canary_count: int, 
                      monitoring_frequency: str = 'rate(5 minutes)') -> Dict:
        """Estimate monthly costs for alarm configuration"""
        
        # Extract frequency from rate expression
        if 'minute' in monitoring_frequency:
            minutes = int(monitoring_frequency.split('(')[1].split(' ')[0])
            executions_per_month = (30 * 24 * 60) // minutes
        elif 'hour' in monitoring_frequency:
            hours = int(monitoring_frequency.split('(')[1].split(' ')[0])
            executions_per_month = (30 * 24) // hours
        else:
            executions_per_month = 30 * 24 * 12  # Default to 5 minutes
        
        # AWS pricing (as of 2024, may vary by region)
        costs = {
            'canary_executions': {
                'count': executions_per_month * canary_count,
                'cost_per_execution': 0.0017,  # $0.0017 per canary execution
                'total': executions_per_month * canary_count * 0.0017
            },
            'alarm_evaluations': {
                'count': len(config['alarmConfigurations']) * canary_count * executions_per_month,
                'cost_per_evaluation': 0.10 / 1000,  # $0.10 per 1000 evaluations
                'total': (len(config['alarmConfigurations']) * canary_count * executions_per_month * 0.10) / 1000
            },
            'sns_notifications': {
                'estimated_notifications': 100,  # Estimated monthly notifications
                'cost_per_notification': 0.50 / 1000,  # $0.50 per 1000 notifications
                'total': (100 * 0.50) / 1000
            }
        }
        
        total_cost = sum(item['total'] for item in costs.values())
        costs['total_monthly_cost'] = total_cost
        
        return costs
    
    def generate_deployment_script(self, config: Dict, stack_name: str, 
                                 output_file: str = 'deploy-alarms.sh') -> None:
        """Generate deployment script for alarms"""
        
        script_content = f"""#!/bin/bash
# Auto-generated alarm deployment script
# Generated on: {datetime.now().isoformat()}

set -e

STACK_NAME="{stack_name}"
REGION="${{AWS_DEFAULT_REGION:-us-east-1}}"

echo "Deploying CloudWatch alarms for stack: $STACK_NAME"
echo "Region: $REGION"

# Validate AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "Error: AWS CLI not configured or no valid credentials"
    exit 1
fi

# Get stack outputs
echo "Retrieving stack outputs..."
NOTIFICATION_TOPIC=$(aws cloudformation describe-stacks \\
    --stack-name $STACK_NAME \\
    --region $REGION \\
    --query 'Stacks[0].Outputs[?OutputKey==`AlarmNotificationTopicArn`].OutputValue' \\
    --output text)

if [ -z "$NOTIFICATION_TOPIC" ]; then
    echo "Error: Could not retrieve notification topic ARN from stack"
    exit 1
fi

echo "Notification Topic: $NOTIFICATION_TOPIC"

# Get canary names
CANARIES=$(aws synthetics describe-canaries \\
    --region $REGION \\
    --query 'Canaries[?contains(Name, `{stack_name.lower()}`)].Name' \\
    --output text)

if [ -z "$CANARIES" ]; then
    echo "Warning: No canaries found for stack $STACK_NAME"
fi

echo "Found canaries: $CANARIES"

# Create alarms using alarm manager
python3 alarm-manager.py create-all \\
    --canaries $CANARIES \\
    --notification-topic $NOTIFICATION_TOPIC \\
    --region $REGION

echo "Alarm deployment completed successfully!"
"""
        
        with open(output_file, 'w') as f:
            f.write(script_content)
        
        # Make script executable
        import os
        os.chmod(output_file, 0o755)
        
        print(f"✓ Generated deployment script: {output_file}")


def main():
    parser = argparse.ArgumentParser(description='CloudWatch Synthetics Alarm Manager')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--config', default='alarm-config.json', help='Alarm configuration file')
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Validate command
    validate_parser = subparsers.add_parser('validate', help='Validate alarm configuration')
    
    # List command
    list_parser = subparsers.add_parser('list', help='List canaries and alarms')
    
    # Create command
    create_parser = subparsers.add_parser('create-all', help='Create all alarms for canaries')
    create_parser.add_argument('--canaries', nargs='+', required=True, help='Canary names')
    create_parser.add_argument('--notification-topic', required=True, help='SNS topic ARN for notifications')
    create_parser.add_argument('--alarm-threshold', type=int, default=2, help='Alarm threshold')
    create_parser.add_argument('--escalation-threshold', type=int, default=5, help='Escalation threshold')
    create_parser.add_argument('--high-latency-threshold', type=int, default=5000, help='High latency threshold (ms)')
    
    # Cost estimation command
    cost_parser = subparsers.add_parser('estimate-costs', help='Estimate monthly costs')
    cost_parser.add_argument('--canary-count', type=int, required=True, help='Number of canaries')
    cost_parser.add_argument('--frequency', default='rate(5 minutes)', help='Monitoring frequency')
    
    # Generate script command
    script_parser = subparsers.add_parser('generate-script', help='Generate deployment script')
    script_parser.add_argument('--stack-name', required=True, help='CloudFormation stack name')
    script_parser.add_argument('--output', default='deploy-alarms.sh', help='Output script file')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    manager = AlarmManager(args.region)
    config = manager.load_alarm_config(args.config)
    
    if args.command == 'validate':
        if manager.validate_configuration(config):
            print("✓ Configuration is valid")
        else:
            sys.exit(1)
    
    elif args.command == 'list':
        canaries = manager.list_canaries()
        print(f"Found {len(canaries)} canaries:")
        for canary in canaries:
            print(f"  - {canary['Name']} (Status: {canary['Status']['State']})")
    
    elif args.command == 'create-all':
        success_count = 0
        total_alarms = len(config['alarmConfigurations']) * len(args.canaries)
        
        for canary_name in args.canaries:
            for alarm_type, alarm_config in config['alarmConfigurations'].items():
                if manager.create_alarm(
                    alarm_config, canary_name, alarm_type, 
                    args.notification_topic,
                    alarmThreshold=args.alarm_threshold,
                    escalationThreshold=args.escalation_threshold,
                    threshold=args.high_latency_threshold
                ):
                    success_count += 1
        
        # Create composite alarm
        if manager.create_composite_alarm(args.canaries, args.notification_topic):
            success_count += 1
            total_alarms += 1
        
        print(f"\\nCreated {success_count}/{total_alarms} alarms successfully")
    
    elif args.command == 'estimate-costs':
        costs = manager.estimate_costs(config, args.canary_count, args.frequency)
        
        print("\\nMonthly Cost Estimation:")
        print("=" * 50)
        print(f"Canary Executions: ${costs['canary_executions']['total']:.2f}")
        print(f"  - {costs['canary_executions']['count']:,} executions @ ${costs['canary_executions']['cost_per_execution']:.4f} each")
        print(f"Alarm Evaluations: ${costs['alarm_evaluations']['total']:.2f}")
        print(f"  - {costs['alarm_evaluations']['count']:,} evaluations @ ${costs['alarm_evaluations']['cost_per_evaluation']:.6f} each")
        print(f"SNS Notifications: ${costs['sns_notifications']['total']:.2f}")
        print(f"  - {costs['sns_notifications']['estimated_notifications']} notifications @ ${costs['sns_notifications']['cost_per_notification']:.6f} each")
        print("-" * 50)
        print(f"Total Monthly Cost: ${costs['total_monthly_cost']:.2f}")
    
    elif args.command == 'generate-script':
        manager.generate_deployment_script(config, args.stack_name, args.output)


if __name__ == '__main__':
    main()