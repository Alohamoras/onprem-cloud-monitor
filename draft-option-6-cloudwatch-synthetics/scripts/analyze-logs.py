#!/usr/bin/env python3

"""
CloudWatch Logs Analysis Script for Synthetics Canaries

This script provides utilities for analyzing canary logs and generating
insights about performance, errors, and trends.
"""

import boto3
import json
import argparse
import sys
from datetime import datetime, timedelta
from collections import defaultdict, Counter
import statistics

class CanaryLogAnalyzer:
    def __init__(self, region='us-east-1'):
        self.logs_client = boto3.client('logs', region_name=region)
        self.region = region
    
    def get_log_groups(self, canary_name_pattern=None):
        """Get all canary log groups"""
        paginator = self.logs_client.get_paginator('describe_log_groups')
        log_groups = []
        
        for page in paginator.paginate():
            for group in page['logGroups']:
                group_name = group['logGroupName']
                if '/aws/lambda/cwsyn-' in group_name:
                    if not canary_name_pattern or canary_name_pattern in group_name:
                        log_groups.append(group_name)
        
        return log_groups
    
    def query_logs(self, log_group, query, start_time, end_time):
        """Execute CloudWatch Logs Insights query"""
        try:
            response = self.logs_client.start_query(
                logGroupName=log_group,
                startTime=int(start_time.timestamp()),
                endTime=int(end_time.timestamp()),
                queryString=query
            )
            
            query_id = response['queryId']
            
            # Wait for query to complete
            while True:
                result = self.logs_client.get_query_results(queryId=query_id)
                if result['status'] == 'Complete':
                    return result['results']
                elif result['status'] == 'Failed':
                    raise Exception(f"Query failed: {result.get('statistics', {})}")
                
                import time
                time.sleep(1)
                
        except Exception as e:
            print(f"Error querying logs: {e}")
            return []
    
    def analyze_errors(self, log_group, hours=24):
        """Analyze error patterns in canary logs"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours)
        
        query = """
        fields @timestamp, level, message, errorCategory, error, canaryName
        | filter level = "ERROR"
        | sort @timestamp desc
        """
        
        results = self.query_logs(log_group, query, start_time, end_time)
        
        if not results:
            print(f"No error logs found in {log_group} for the last {hours} hours")
            return
        
        # Parse results
        errors = []
        for result in results:
            error_data = {}
            for field in result:
                if field['field'] == '@timestamp':
                    error_data['timestamp'] = field['value']
                elif field['field'] == 'errorCategory':
                    error_data['category'] = field['value']
                elif field['field'] == 'error':
                    error_data['error'] = field['value']
                elif field['field'] == 'message':
                    error_data['message'] = field['value']
            errors.append(error_data)
        
        # Analyze error patterns
        error_categories = Counter(error.get('category', 'UNKNOWN') for error in errors)
        
        print(f"\n=== Error Analysis for {log_group} ===")
        print(f"Time Range: {start_time.strftime('%Y-%m-%d %H:%M')} - {end_time.strftime('%Y-%m-%d %H:%M')}")
        print(f"Total Errors: {len(errors)}")
        print("\nError Categories:")
        for category, count in error_categories.most_common():
            percentage = (count / len(errors)) * 100
            print(f"  {category}: {count} ({percentage:.1f}%)")
        
        # Recent errors
        print(f"\nRecent Errors (last 10):")
        for error in errors[:10]:
            timestamp = error.get('timestamp', 'Unknown')
            category = error.get('category', 'UNKNOWN')
            message = error.get('error', error.get('message', 'No message'))[:100]
            print(f"  {timestamp} [{category}] {message}")
    
    def analyze_performance(self, log_group, hours=24):
        """Analyze performance trends in canary logs"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours)
        
        query = """
        fields @timestamp, responseTime, performanceCategory, statusCode
        | filter level = "INFO" and (message = "API check successful" or message = "Heartbeat check successful")
        | sort @timestamp desc
        """
        
        results = self.query_logs(log_group, query, start_time, end_time)
        
        if not results:
            print(f"No performance data found in {log_group} for the last {hours} hours")
            return
        
        # Parse results
        performance_data = []
        for result in results:
            data = {}
            for field in result:
                if field['field'] == '@timestamp':
                    data['timestamp'] = field['value']
                elif field['field'] == 'responseTime':
                    try:
                        data['responseTime'] = float(field['value'])
                    except (ValueError, TypeError):
                        data['responseTime'] = None
                elif field['field'] == 'performanceCategory':
                    data['category'] = field['value']
                elif field['field'] == 'statusCode':
                    try:
                        data['statusCode'] = int(field['value'])
                    except (ValueError, TypeError):
                        data['statusCode'] = None
            performance_data.append(data)
        
        # Filter valid response times
        response_times = [d['responseTime'] for d in performance_data if d.get('responseTime') is not None]
        performance_categories = Counter(d.get('category', 'UNKNOWN') for d in performance_data)
        status_codes = Counter(d.get('statusCode') for d in performance_data if d.get('statusCode') is not None)
        
        print(f"\n=== Performance Analysis for {log_group} ===")
        print(f"Time Range: {start_time.strftime('%Y-%m-%d %H:%M')} - {end_time.strftime('%Y-%m-%d %H:%M')}")
        print(f"Total Successful Checks: {len(performance_data)}")
        
        if response_times:
            print(f"\nResponse Time Statistics:")
            print(f"  Average: {statistics.mean(response_times):.1f}ms")
            print(f"  Median: {statistics.median(response_times):.1f}ms")
            print(f"  Min: {min(response_times):.1f}ms")
            print(f"  Max: {max(response_times):.1f}ms")
            if len(response_times) > 1:
                print(f"  Std Dev: {statistics.stdev(response_times):.1f}ms")
        
        print(f"\nPerformance Categories:")
        for category, count in performance_categories.most_common():
            percentage = (count / len(performance_data)) * 100
            print(f"  {category}: {count} ({percentage:.1f}%)")
        
        print(f"\nStatus Code Distribution:")
        for code, count in status_codes.most_common():
            percentage = (count / len(performance_data)) * 100
            print(f"  {code}: {count} ({percentage:.1f}%)")
    
    def analyze_trends(self, log_group, hours=24):
        """Analyze trends over time"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours)
        
        # Query for hourly success/failure rates
        query = """
        fields @timestamp, level, message
        | filter level = "INFO" or level = "ERROR"
        | stats count() by bin(1h), level
        """
        
        results = self.query_logs(log_group, query, start_time, end_time)
        
        if not results:
            print(f"No trend data found in {log_group} for the last {hours} hours")
            return
        
        # Parse and organize results
        hourly_data = defaultdict(lambda: {'INFO': 0, 'ERROR': 0})
        
        for result in results:
            bin_time = None
            level = None
            count = 0
            
            for field in result:
                if field['field'] == 'bin(1h)':
                    bin_time = field['value']
                elif field['field'] == 'level':
                    level = field['value']
                elif field['field'] == 'count()':
                    try:
                        count = int(field['value'])
                    except (ValueError, TypeError):
                        count = 0
            
            if bin_time and level:
                hourly_data[bin_time][level] = count
        
        print(f"\n=== Trend Analysis for {log_group} ===")
        print(f"Time Range: {start_time.strftime('%Y-%m-%d %H:%M')} - {end_time.strftime('%Y-%m-%d %H:%M')}")
        print(f"\nHourly Success/Error Rates:")
        print(f"{'Time':<20} {'Success':<10} {'Errors':<10} {'Success Rate':<15}")
        print("-" * 60)
        
        for bin_time in sorted(hourly_data.keys()):
            success_count = hourly_data[bin_time]['INFO']
            error_count = hourly_data[bin_time]['ERROR']
            total = success_count + error_count
            success_rate = (success_count / total * 100) if total > 0 else 0
            
            # Format timestamp
            try:
                dt = datetime.fromisoformat(bin_time.replace('Z', '+00:00'))
                time_str = dt.strftime('%Y-%m-%d %H:%M')
            except:
                time_str = bin_time[:19]
            
            print(f"{time_str:<20} {success_count:<10} {error_count:<10} {success_rate:.1f}%")
    
    def generate_report(self, canary_name_pattern=None, hours=24):
        """Generate comprehensive analysis report"""
        log_groups = self.get_log_groups(canary_name_pattern)
        
        if not log_groups:
            print("No canary log groups found")
            return
        
        print(f"Found {len(log_groups)} canary log groups:")
        for group in log_groups:
            print(f"  - {group}")
        
        for log_group in log_groups:
            print(f"\n{'='*80}")
            print(f"ANALYZING: {log_group}")
            print(f"{'='*80}")
            
            try:
                self.analyze_errors(log_group, hours)
                self.analyze_performance(log_group, hours)
                self.analyze_trends(log_group, hours)
            except Exception as e:
                print(f"Error analyzing {log_group}: {e}")

def main():
    parser = argparse.ArgumentParser(description='Analyze CloudWatch Synthetics canary logs')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--canary', help='Canary name pattern to filter log groups')
    parser.add_argument('--hours', type=int, default=24, help='Hours of logs to analyze')
    parser.add_argument('--analysis', choices=['errors', 'performance', 'trends', 'all'], 
                       default='all', help='Type of analysis to perform')
    
    args = parser.parse_args()
    
    analyzer = CanaryLogAnalyzer(region=args.region)
    
    if args.analysis == 'all':
        analyzer.generate_report(args.canary, args.hours)
    else:
        log_groups = analyzer.get_log_groups(args.canary)
        if not log_groups:
            print("No canary log groups found")
            return
        
        for log_group in log_groups:
            if args.analysis == 'errors':
                analyzer.analyze_errors(log_group, args.hours)
            elif args.analysis == 'performance':
                analyzer.analyze_performance(log_group, args.hours)
            elif args.analysis == 'trends':
                analyzer.analyze_trends(log_group, args.hours)

if __name__ == '__main__':
    main()