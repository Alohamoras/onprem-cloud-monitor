#!/usr/bin/env python3
"""
On-Premises Container Monitor
Sends heartbeat metrics to AWS CloudWatch and optionally monitors target systems
"""

import os
import sys
import time
import socket
import logging
import threading
import signal
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any

import boto3
from botocore.exceptions import ClientError, NoCredentialsError
from flask import Flask, jsonify

# Configure logging
def setup_logging():
    log_level = os.getenv('LOG_LEVEL', 'INFO').upper()
    logging.basicConfig(
        level=getattr(logging, log_level),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        stream=sys.stdout
    )
    return logging.getLogger(__name__)

logger = setup_logging()

class ContainerMonitor:
    def __init__(self):
        """Initialize the container monitor with configuration from environment variables"""
        self.config = self._load_config()
        self.cloudwatch = None
        self.running = False
        self.start_time = time.time()
        self.last_heartbeat = None
        self.target_status = {}
        
        # Initialize CloudWatch client
        try:
            self.cloudwatch = boto3.client(
                'cloudwatch',
                region_name=self.config['aws_region'],
                aws_access_key_id=self.config.get('aws_access_key_id'),
                aws_secret_access_key=self.config.get('aws_secret_access_key')
            )
            # Test credentials
            self.cloudwatch.list_metrics(MaxRecords=1)
            logger.info("AWS CloudWatch client initialized successfully")
        except NoCredentialsError:
            logger.error("AWS credentials not found. Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY")
            sys.exit(1)
        except ClientError as e:
            logger.error(f"AWS credentials error: {e}")
            sys.exit(1)
        except Exception as e:
            logger.error(f"Failed to initialize CloudWatch client: {e}")
            sys.exit(1)

    def _load_config(self) -> Dict[str, Any]:
        """Load configuration from environment variables"""
        config = {
            # Required AWS configuration
            'aws_access_key_id': os.getenv('AWS_ACCESS_KEY_ID'),
            'aws_secret_access_key': os.getenv('AWS_SECRET_ACCESS_KEY'),
            'aws_region': os.getenv('AWS_REGION', 'us-east-1'),
            
            # Container identification
            'container_name': os.getenv('CONTAINER_NAME', socket.gethostname()),
            
            # Heartbeat configuration
            'heartbeat_interval': int(os.getenv('HEARTBEAT_INTERVAL', '300')),
            'cloudwatch_namespace': os.getenv('CLOUDWATCH_NAMESPACE', 'ContainerMonitoring/Heartbeat'),
            
            # Optional target monitoring
            'monitor_targets': self._parse_targets(os.getenv('MONITOR_TARGETS', '')),
            'target_port': int(os.getenv('TARGET_PORT', '80')),
            'target_timeout': int(os.getenv('TARGET_TIMEOUT', '5')),
            
            # Health endpoint
            'enable_health_endpoint': os.getenv('ENABLE_HEALTH_ENDPOINT', 'false').lower() == 'true',
            'health_port': int(os.getenv('HEALTH_PORT', '8080')),
        }
        
        # Validate required configuration
        if not config['aws_access_key_id'] or not config['aws_secret_access_key']:
            logger.error("AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set")
            sys.exit(1)
        
        logger.info(f"Configuration loaded:")
        logger.info(f"  Container Name: {config['container_name']}")
        logger.info(f"  AWS Region: {config['aws_region']}")
        logger.info(f"  Heartbeat Interval: {config['heartbeat_interval']}s")
        logger.info(f"  CloudWatch Namespace: {config['cloudwatch_namespace']}")
        logger.info(f"  Monitor Targets: {len(config['monitor_targets'])} targets")
        logger.info(f"  Health Endpoint: {config['enable_health_endpoint']}")
        
        return config

    def _parse_targets(self, targets_str: str) -> List[str]:
        """Parse comma-separated target list"""
        if not targets_str:
            return []
        return [target.strip() for target in targets_str.split(',') if target.strip()]

    def send_heartbeat(self):
        """Send heartbeat metrics to CloudWatch"""
        try:
            current_time = datetime.now(timezone.utc)
            uptime = time.time() - self.start_time
            
            metrics = [
                {
                    'MetricName': 'ContainerHeartbeat',
                    'Dimensions': [
                        {'Name': 'ContainerName', 'Value': self.config['container_name']},
                        {'Name': 'Region', 'Value': self.config['aws_region']}
                    ],
                    'Value': 1.0,
                    'Unit': 'Count',
                    'Timestamp': current_time
                },
                {
                    'MetricName': 'ContainerUptime',
                    'Dimensions': [
                        {'Name': 'ContainerName', 'Value': self.config['container_name']},
                        {'Name': 'Region', 'Value': self.config['aws_region']}
                    ],
                    'Value': uptime,
                    'Unit': 'Seconds',
                    'Timestamp': current_time
                }
            ]
            
            self.cloudwatch.put_metric_data(
                Namespace=self.config['cloudwatch_namespace'],
                MetricData=metrics
            )
            
            self.last_heartbeat = current_time
            logger.info(f"Heartbeat sent successfully (uptime: {uptime:.0f}s)")
            
        except Exception as e:
            logger.error(f"Failed to send heartbeat: {e}")

    def check_target_connectivity(self, target_ip: str) -> tuple[bool, float]:
        """Check connectivity to a target IP/hostname"""
        start_time = time.time()
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(self.config['target_timeout'])
            result = sock.connect_ex((target_ip, self.config['target_port']))
            sock.close()
            
            duration = (time.time() - start_time) * 1000  # Convert to milliseconds
            is_online = result == 0
            
            logger.debug(f"Target {target_ip}:{self.config['target_port']} - {'ONLINE' if is_online else 'OFFLINE'} ({duration:.1f}ms)")
            return is_online, duration
            
        except Exception as e:
            duration = (time.time() - start_time) * 1000
            logger.warning(f"Target {target_ip} check failed: {e}")
            return False, duration

    def send_target_metrics(self):
        """Check targets and send metrics"""
        if not self.config['monitor_targets']:
            return
        
        try:
            current_time = datetime.now(timezone.utc)
            metrics = []
            
            for target in self.config['monitor_targets']:
                is_online, response_time = self.check_target_connectivity(target)
                
                # Store status for health endpoint
                self.target_status[target] = {
                    'online': is_online,
                    'response_time': response_time,
                    'last_check': current_time.isoformat()
                }
                
                # Target status metric
                metrics.append({
                    'MetricName': 'TargetStatus',
                    'Dimensions': [
                        {'Name': 'ContainerName', 'Value': self.config['container_name']},
                        {'Name': 'TargetIP', 'Value': target},
                        {'Name': 'TargetPort', 'Value': str(self.config['target_port'])}
                    ],
                    'Value': 1.0 if is_online else 0.0,
                    'Unit': 'Count',
                    'Timestamp': current_time
                })
                
                # Response time metric (only for online targets)
                if is_online:
                    metrics.append({
                        'MetricName': 'TargetResponseTime',
                        'Dimensions': [
                            {'Name': 'ContainerName', 'Value': self.config['container_name']},
                            {'Name': 'TargetIP', 'Value': target},
                            {'Name': 'TargetPort', 'Value': str(self.config['target_port'])}
                        ],
                        'Value': response_time,
                        'Unit': 'Milliseconds',
                        'Timestamp': current_time
                    })
            
            if metrics:
                # Send metrics in batches of 20 (CloudWatch limit)
                for i in range(0, len(metrics), 20):
                    batch = metrics[i:i+20]
                    self.cloudwatch.put_metric_data(
                        Namespace=self.config['cloudwatch_namespace'],
                        MetricData=batch
                    )
                
                online_count = sum(1 for status in self.target_status.values() if status['online'])
                total_count = len(self.target_status)
                logger.info(f"Target metrics sent: {online_count}/{total_count} online")
            
        except Exception as e:
            logger.error(f"Failed to send target metrics: {e}")

    def run_health_endpoint(self):
        """Run Flask health endpoint"""
        app = Flask(__name__)
        app.logger.setLevel(logging.WARNING)  # Reduce Flask logging
        
        @app.route('/health')
        def health():
            """Health check endpoint"""
            uptime = time.time() - self.start_time
            health_data = {
                'status': 'healthy' if self.running else 'unhealthy',
                'container_name': self.config['container_name'],
                'uptime_seconds': round(uptime, 1),
                'last_heartbeat': self.last_heartbeat.isoformat() if self.last_heartbeat else None,
                'target_status': self.target_status if self.config['monitor_targets'] else None,
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
            return jsonify(health_data)
        
        @app.route('/metrics')
        def metrics():
            """Prometheus-style metrics endpoint (optional)"""
            uptime = time.time() - self.start_time
            metrics = [
                f'container_heartbeat{{container_name="{self.config["container_name"]}"}} 1',
                f'container_uptime_seconds{{container_name="{self.config["container_name"]}"}} {uptime:.1f}'
            ]
            
            for target, status in self.target_status.items():
                metrics.append(f'target_status{{container_name="{self.config["container_name"]}",target="{target}"}} {1 if status["online"] else 0}')
                if status['online']:
                    metrics.append(f'target_response_time_ms{{container_name="{self.config["container_name"]}",target="{target}"}} {status["response_time"]:.1f}')
            
            return '\n'.join(metrics) + '\n', 200, {'Content-Type': 'text/plain'}
        
        try:
            app.run(host='0.0.0.0', port=self.config['health_port'], debug=False)
        except Exception as e:
            logger.error(f"Health endpoint failed: {e}")

    def run(self):
        """Main monitoring loop"""
        logger.info("Starting Container Monitor")
        logger.info(f"Container: {self.config['container_name']}")
        logger.info(f"Heartbeat interval: {self.config['heartbeat_interval']}s")
        
        self.running = True
        
        # Start health endpoint in background thread if enabled
        if self.config['enable_health_endpoint']:
            health_thread = threading.Thread(target=self.run_health_endpoint, daemon=True)
            health_thread.start()
            logger.info(f"Health endpoint started on port {self.config['health_port']}")
        
        # Send initial heartbeat
        self.send_heartbeat()
        if self.config['monitor_targets']:
            self.send_target_metrics()
        
        # Main monitoring loop
        try:
            while self.running:
                time.sleep(self.config['heartbeat_interval'])
                
                if not self.running:
                    break
                
                # Send heartbeat
                self.send_heartbeat()
                
                # Check targets if configured
                if self.config['monitor_targets']:
                    self.send_target_metrics()
                
        except KeyboardInterrupt:
            logger.info("Received interrupt signal")
        except Exception as e:
            logger.error(f"Monitoring loop error: {e}")
        finally:
            self.running = False
            logger.info("Container Monitor stopped")

    def stop(self):
        """Stop the monitor gracefully"""
        logger.info("Stopping Container Monitor...")
        self.running = False

def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logger.info(f"Received signal {signum}")
    if 'monitor' in globals():
        monitor.stop()
    sys.exit(0)

if __name__ == "__main__":
    # Set up signal handlers for graceful shutdown
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    # Create and run monitor
    monitor = ContainerMonitor()
    monitor.run()