import json
import boto3
import socket
import time
from datetime import datetime
from typing import List, Dict, Tuple

# Configuration
SNOWBALL_DEVICES = [
    "10.0.0.1"
]
SNOWBALL_PORT = 8443
TIMEOUT = 5

# AWS clients
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Main Lambda handler for Snowball monitoring
    """
    print(f"Starting Snowball monitoring at {datetime.now().isoformat()}")
    
    try:
        # Check connectivity for all devices
        device_results = check_all_devices()
        
        # Send metrics to CloudWatch (CloudWatch alarms will handle alerting)
        send_metrics(device_results)
        
        # Prepare response
        online_count = sum(1 for result in device_results.values() if result['online'])
        offline_count = len(device_results) - online_count
        
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'timestamp': datetime.now().isoformat(),
                'total_devices': len(SNOWBALL_DEVICES),
                'online_count': online_count,
                'offline_count': offline_count,
                'device_status': device_results
            })
        }
        
        print(f"Monitoring complete: {online_count} online, {offline_count} offline")
        return response
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def check_device_connectivity(device_ip: str, port: int = SNOWBALL_PORT, timeout: int = TIMEOUT) -> Tuple[bool, float]:
    """
    Check if a single Snowball device is reachable
    """
    start_time = time.time()
    
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((device_ip, port))
        sock.close()
        
        duration = time.time() - start_time
        is_online = result == 0
        
        print(f"Device {device_ip}: {'ONLINE' if is_online else 'OFFLINE'} ({duration:.3f}s)")
        return is_online, duration
        
    except Exception as e:
        duration = time.time() - start_time
        print(f"Device {device_ip}: ERROR - {str(e)} ({duration:.3f}s)")
        return False, duration

def check_all_devices() -> Dict[str, Dict]:
    """
    Check connectivity for all configured devices
    """
    results = {}
    
    for device_ip in SNOWBALL_DEVICES:
        is_online, duration = check_device_connectivity(device_ip)
        results[device_ip] = {
            'online': is_online,
            'duration': duration,
            'timestamp': datetime.now().isoformat()
        }
    
    return results

def send_metrics(device_results: Dict[str, Dict]):
    """
    Send metrics to CloudWatch for alarm monitoring
    """
    metric_data = []
    online_count = 0
    offline_count = 0
    
    # Individual device metrics
    for device_ip, result in device_results.items():
        metric_value = 1 if result['online'] else 0
        if result['online']:
            online_count += 1
        else:
            offline_count += 1
            
        metric_data.append({
            'MetricName': 'DeviceStatus',
            'Dimensions': [
                {
                    'Name': 'DeviceIP',
                    'Value': device_ip
                }
            ],
            'Value': metric_value,
            'Unit': 'Count',
            'Timestamp': datetime.now()
        })
        
        # Add response time metric for online devices
        if result['online']:
            metric_data.append({
                'MetricName': 'ResponseTime',
                'Dimensions': [
                    {
                        'Name': 'DeviceIP',
                        'Value': device_ip
                    }
                ],
                'Value': result['duration'] * 1000,  # Convert to milliseconds
                'Unit': 'Milliseconds',
                'Timestamp': datetime.now()
            })
    
    # Summary metrics (these are what your alarms monitor)
    metric_data.extend([
        {
            'MetricName': 'TotalOnline',
            'Value': online_count,
            'Unit': 'Count',
            'Timestamp': datetime.now()
        },
        {
            'MetricName': 'TotalOffline', 
            'Value': offline_count,
            'Unit': 'Count',
            'Timestamp': datetime.now()
        },
        {
            'MetricName': 'TotalDevices',
            'Value': len(SNOWBALL_DEVICES),
            'Unit': 'Count',
            'Timestamp': datetime.now()
        }
    ])
    
    # Send metrics in batches (CloudWatch limit is 20 per request)
    for i in range(0, len(metric_data), 20):
        batch = metric_data[i:i+20]
        try:
            cloudwatch.put_metric_data(
                Namespace='Snowball/MultiDevice',
                MetricData=batch
            )
            print(f"Sent {len(batch)} metrics to CloudWatch")
        except Exception as e:
            print(f"Error sending metrics: {str(e)}")
            raise  # Re-raise to trigger Lambda error for monitoring