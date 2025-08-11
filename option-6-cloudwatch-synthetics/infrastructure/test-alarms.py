#!/usr/bin/env python3
"""
CloudWatch Synthetics Alarm Testing Utility

This script provides utilities for testing CloudWatch alarms by simulating
failure conditions and validating alarm behavior.
"""

import boto3
import json
import time
import argparse
from datetime import datetime, timedelta
from typing import Dict, List


class AlarmTester:
    """Tests CloudWatch alarms for Synthetics canaries"""
    
    def __init__(self, region: str = 'us-east-1'):
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        self.synthetics = boto3.client('synthetics', region_name=region)
        self.region = region
    
    def list_alarms(self, alarm_prefix: str = None) -> List[Dict]:
        """List CloudWatch alarms, optionally filtered by prefix"""
        try:
            if alarm_prefix:
                response = self.cloudwatch.describe_alarms(
                    AlarmNamePrefix=alarm_prefix
                )
            else:
                response = self.cloudwatch.describe_alarms()
            
            return response.get('MetricAlarms', []) + response.get('CompositeAlarms', [])
        except Exception as e:
            print(f"Error listing alarms: {e}")
            return []
    
    def get_alarm_state(self, alarm_name: str) -> Dict:
        """Get current state of an alarm"""
        try:
            response = self.cloudwatch.describe_alarms(
                AlarmNames=[alarm_name]
            )
            
            alarms = response.get('MetricAlarms', []) + response.get('CompositeAlarms', [])
            if alarms:
                alarm = alarms[0]
                return {
                    'name': alarm['AlarmName'],
                    'state': alarm['StateValue'],
                    'reason': alarm['StateReason'],
                    'updated': alarm['StateUpdatedTimestamp']
                }
            else:
                return {'error': f'Alarm {alarm_name} not found'}
        except Exception as e:
            return {'error': str(e)}
    
    def simulate_canary_failure(self, canary_name: str, duration_minutes: int = 10) -> bool:
        """Simulate canary failure by stopping the canary temporarily"""
        try:
            print(f"Stopping canary {canary_name} to simulate failure...")
            
            # Stop the canary
            self.synthetics.stop_canary(Name=canary_name)
            
            print(f"Canary stopped. Waiting {duration_minutes} minutes for alarm to trigger...")
            time.sleep(duration_minutes * 60)
            
            # Restart the canary
            print(f"Restarting canary {canary_name}...")
            self.synthetics.start_canary(Name=canary_name)
            
            print("Canary restarted. Monitor alarms for recovery.")
            return True
            
        except Exception as e:
            print(f"Error simulating failure: {e}")
            return False
    
    def put_custom_metric(self, canary_name: str, metric_name: str, 
                         value: float, unit: str = 'Count') -> bool:
        """Put custom metric data to trigger alarms"""
        try:
            self.cloudwatch.put_metric_data(
                Namespace='CloudWatchSynthetics/UserAgentMetrics',
                MetricData=[
                    {
                        'MetricName': metric_name,
                        'Dimensions': [
                            {
                                'Name': 'CanaryName',
                                'Value': canary_name
                            }
                        ],
                        'Value': value,
                        'Unit': unit,
                        'Timestamp': datetime.utcnow()
                    }
                ]
            )
            print(f"✓ Put metric {metric_name}={value} for canary {canary_name}")
            return True
        except Exception as e:
            print(f"✗ Failed to put metric: {e}")
            return False
    
    def test_high_latency_alarm(self, canary_name: str, latency_ms: int = 10000) -> bool:
        """Test high latency alarm by putting high response time metrics"""
        return self.put_custom_metric(
            canary_name, 'ResponseTime', latency_ms, 'Milliseconds'
        )
    
    def test_failure_alarm(self, canary_name: str) -> bool:
        """Test failure alarm by putting failure metrics"""
        return self.put_custom_metric(canary_name, 'HeartbeatFailure', 1)
    
    def monitor_alarm_states(self, alarm_names: List[str], 
                           duration_minutes: int = 15) -> Dict:
        """Monitor alarm states over time"""
        print(f"Monitoring {len(alarm_names)} alarms for {duration_minutes} minutes...")
        
        results = {alarm_name: [] for alarm_name in alarm_names}
        start_time = datetime.utcnow()
        end_time = start_time + timedelta(minutes=duration_minutes)
        
        while datetime.utcnow() < end_time:
            timestamp = datetime.utcnow()
            
            for alarm_name in alarm_names:
                state = self.get_alarm_state(alarm_name)
                state['timestamp'] = timestamp
                results[alarm_name].append(state)
            
            print(f"[{timestamp.strftime('%H:%M:%S')}] States: " + 
                  ", ".join([f"{name}: {results[name][-1].get('state', 'ERROR')}" 
                           for name in alarm_names]))
            
            time.sleep(60)  # Check every minute
        
        return results
    
    def validate_alarm_configuration(self, alarm_name: str) -> Dict:
        """Validate alarm configuration against best practices"""
        try:
            response = self.cloudwatch.describe_alarms(
                AlarmNames=[alarm_name]
            )
            
            alarms = response.get('MetricAlarms', [])
            if not alarms:
                return {'error': f'Alarm {alarm_name} not found'}
            
            alarm = alarms[0]
            validation_results = {
                'alarm_name': alarm_name,
                'issues': [],
                'recommendations': []
            }
            
            # Check evaluation periods
            if alarm['EvaluationPeriods'] < 2:
                validation_results['issues'].append(
                    'Evaluation periods < 2 may cause false alarms'
                )
            
            # Check period
            if alarm['Period'] < 300:
                validation_results['recommendations'].append(
                    'Consider using period >= 300 seconds to reduce costs'
                )
            
            # Check missing data treatment
            if alarm['TreatMissingData'] == 'missing':
                validation_results['issues'].append(
                    'TreatMissingData should be set to "breaching" or "notBreaching"'
                )
            
            # Check alarm actions
            if not alarm.get('AlarmActions'):
                validation_results['issues'].append(
                    'No alarm actions configured - notifications will not be sent'
                )
            
            if not alarm.get('OKActions'):
                validation_results['recommendations'].append(
                    'Consider adding OK actions for recovery notifications'
                )
            
            return validation_results
            
        except Exception as e:
            return {'error': str(e)}
    
    def generate_test_report(self, test_results: Dict, output_file: str = None) -> str:
        """Generate a comprehensive test report"""
        report = []
        report.append("CloudWatch Synthetics Alarm Test Report")
        report.append("=" * 50)
        report.append(f"Generated: {datetime.utcnow().isoformat()}")
        report.append("")
        
        for alarm_name, states in test_results.items():
            report.append(f"Alarm: {alarm_name}")
            report.append("-" * 30)
            
            if not states:
                report.append("No data collected")
                continue
            
            # Count state changes
            state_changes = 0
            prev_state = None
            
            for state in states:
                current_state = state.get('state')
                if prev_state and prev_state != current_state:
                    state_changes += 1
                prev_state = current_state
            
            report.append(f"Total state changes: {state_changes}")
            report.append(f"Final state: {states[-1].get('state', 'UNKNOWN')}")
            report.append(f"Final reason: {states[-1].get('reason', 'No reason')}")
            
            # Show state timeline
            report.append("State Timeline:")
            for state in states[-5:]:  # Show last 5 states
                timestamp = state.get('timestamp', 'Unknown')
                if isinstance(timestamp, datetime):
                    timestamp = timestamp.strftime('%H:%M:%S')
                report.append(f"  {timestamp}: {state.get('state', 'UNKNOWN')}")
            
            report.append("")
        
        report_text = "\\n".join(report)
        
        if output_file:
            with open(output_file, 'w') as f:
                f.write(report_text)
            print(f"✓ Test report saved to {output_file}")
        
        return report_text


def main():
    parser = argparse.ArgumentParser(description='CloudWatch Synthetics Alarm Tester')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # List alarms command
    list_parser = subparsers.add_parser('list', help='List alarms')
    list_parser.add_argument('--prefix', help='Alarm name prefix filter')
    
    # Check alarm state command
    state_parser = subparsers.add_parser('state', help='Check alarm state')
    state_parser.add_argument('--alarm-name', required=True, help='Alarm name')
    
    # Simulate failure command
    failure_parser = subparsers.add_parser('simulate-failure', help='Simulate canary failure')
    failure_parser.add_argument('--canary-name', required=True, help='Canary name')
    failure_parser.add_argument('--duration', type=int, default=10, help='Failure duration in minutes')
    
    # Test high latency command
    latency_parser = subparsers.add_parser('test-latency', help='Test high latency alarm')
    latency_parser.add_argument('--canary-name', required=True, help='Canary name')
    latency_parser.add_argument('--latency', type=int, default=10000, help='Latency in milliseconds')
    
    # Monitor alarms command
    monitor_parser = subparsers.add_parser('monitor', help='Monitor alarm states')
    monitor_parser.add_argument('--alarm-names', nargs='+', required=True, help='Alarm names to monitor')
    monitor_parser.add_argument('--duration', type=int, default=15, help='Monitoring duration in minutes')
    monitor_parser.add_argument('--output', help='Output file for test report')
    
    # Validate alarm command
    validate_parser = subparsers.add_parser('validate', help='Validate alarm configuration')
    validate_parser.add_argument('--alarm-name', required=True, help='Alarm name')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    tester = AlarmTester(args.region)
    
    if args.command == 'list':
        alarms = tester.list_alarms(args.prefix)
        print(f"Found {len(alarms)} alarms:")
        for alarm in alarms:
            print(f"  - {alarm['AlarmName']} (State: {alarm['StateValue']})")
    
    elif args.command == 'state':
        state = tester.get_alarm_state(args.alarm_name)
        if 'error' in state:
            print(f"Error: {state['error']}")
        else:
            print(f"Alarm: {state['name']}")
            print(f"State: {state['state']}")
            print(f"Reason: {state['reason']}")
            print(f"Updated: {state['updated']}")
    
    elif args.command == 'simulate-failure':
        if tester.simulate_canary_failure(args.canary_name, args.duration):
            print("Failure simulation completed successfully")
        else:
            print("Failure simulation failed")
    
    elif args.command == 'test-latency':
        if tester.test_high_latency_alarm(args.canary_name, args.latency):
            print(f"High latency metric sent for {args.canary_name}")
            print("Monitor alarms for state changes...")
        else:
            print("Failed to send high latency metric")
    
    elif args.command == 'monitor':
        results = tester.monitor_alarm_states(args.alarm_names, args.duration)
        report = tester.generate_test_report(results, args.output)
        if not args.output:
            print("\\n" + report)
    
    elif args.command == 'validate':
        validation = tester.validate_alarm_configuration(args.alarm_name)
        if 'error' in validation:
            print(f"Error: {validation['error']}")
        else:
            print(f"Validation results for {validation['alarm_name']}:")
            
            if validation['issues']:
                print("\\nIssues found:")
                for issue in validation['issues']:
                    print(f"  ✗ {issue}")
            
            if validation['recommendations']:
                print("\\nRecommendations:")
                for rec in validation['recommendations']:
                    print(f"  ℹ {rec}")
            
            if not validation['issues'] and not validation['recommendations']:
                print("  ✓ No issues found")


if __name__ == '__main__':
    main()