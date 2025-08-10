import json
import socket
import boto3
import time
import logging
from botocore.exceptions import ClientError

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Test Lambda connectivity to Snowballs and AWS services - Debug Version
    """
    logger.info("=== LAMBDA FUNCTION STARTED ===")
    print("Lambda function started - basic print test")
    
    results = {
        'timestamp': time.time(),
        'tests': {},
        'debug_info': {
            'lambda_request_id': context.aws_request_id,
            'remaining_time': context.get_remaining_time_in_millis()
        }
    }
    
    try:
        # Test 1: Snowball connectivity
        logger.info("Starting Snowball connectivity test")
        snowball_ips = ['10.0.0.1']
        
        for ip in snowball_ips:
            try:
                logger.info(f"Testing Snowball connectivity to {ip}")
                start_time = time.time()
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(5)
                result = sock.connect_ex((ip, 8443))
                sock.close()
                duration = time.time() - start_time
                
                logger.info(f"Snowball {ip} test completed in {duration:.2f}s, result: {result}")
                
                results['tests'][f'snowball_{ip}'] = {
                    'status': 'success' if result == 0 else f'failed_code_{result}',
                    'duration': duration,
                    'details': f'Connection result: {result}'
                }
            except Exception as e:
                logger.error(f"Snowball {ip} test failed: {str(e)}")
                results['tests'][f'snowball_{ip}'] = {
                    'status': 'error',
                    'error': str(e)
                }
        
        # Test 2: AWS CloudWatch connectivity
        logger.info("Testing CloudWatch connectivity")
        try:
            cloudwatch = boto3.client('cloudwatch')
            response = cloudwatch.list_metrics()
            logger.info("CloudWatch test successful")
            results['tests']['cloudwatch'] = {
                'status': 'success',
                'metrics_count': len(response.get('Metrics', []))
            }
        except ClientError as e:
            logger.error(f"CloudWatch ClientError: {str(e)}")
            results['tests']['cloudwatch'] = {
                'status': 'error',
                'error': str(e)
            }
        except Exception as e:
            logger.error(f"CloudWatch unexpected error: {str(e)}")
            results['tests']['cloudwatch'] = {
                'status': 'error', 
                'error': f'Unexpected error: {str(e)}'
            }
        
        # Test 3: AWS SNS connectivity
        logger.info("Testing SNS connectivity")
        try:
            sns = boto3.client('sns')
            sns.list_topics()
            logger.info("SNS test successful")
            results['tests']['sns'] = {'status': 'success'}
        except Exception as e:
            logger.error(f"SNS test failed: {str(e)}")
            results['tests']['sns'] = {
                'status': 'error',
                'error': str(e)
            }
        
        # Test 4: DNS resolution
        logger.info("Testing DNS resolution")
        try:
            start_time = time.time()
            ip = socket.gethostbyname('monitoring.us-east-1.amazonaws.com')
            duration = time.time() - start_time
            logger.info(f"DNS test completed in {duration:.2f}s, resolved to {ip}")
            results['tests']['dns_aws'] = {
                'status': 'success',
                'resolved_ip': ip,
                'duration': duration
            }
        except Exception as e:
            logger.error(f"DNS test failed: {str(e)}")
            results['tests']['dns_aws'] = {
                'status': 'error',
                'error': str(e)
            }
        
        # Test 5: Internet connectivity
        logger.info("Testing internet connectivity (expected to work with NAT)")
        try:
            start_time = time.time()
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(3)
            result = sock.connect_ex(('8.8.8.8', 53))
            sock.close()
            duration = time.time() - start_time
            logger.info(f"Internet test completed in {duration:.2f}s, result: {result}")
            results['tests']['internet'] = {
                'status': 'success' if result == 0 else f'failed_code_{result}',
                'duration': duration,
                'note': 'Should work with NAT Gateway'
            }
        except Exception as e:
            logger.error(f"Internet test failed: {str(e)}")
            results['tests']['internet'] = {
                'status': 'error',
                'error': str(e),
                'note': 'Should work with NAT Gateway'
            }
        
        total_duration = time.time() - results['timestamp']
        logger.info(f"Lambda function completed in {total_duration:.2f}s")
        results['debug_info']['total_duration'] = total_duration
        
    except Exception as e:
        logger.error(f"Critical error in lambda_handler: {str(e)}")
        results['critical_error'] = str(e)
    
    logger.info("=== LAMBDA FUNCTION ENDING ===")
    return {
        'statusCode': 200,
        'body': json.dumps(results, indent=2)
    }