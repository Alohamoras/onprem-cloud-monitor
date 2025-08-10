#!/usr/bin/env python3
"""
Docker health check script
Used by Docker HEALTHCHECK to verify container is running properly
"""

import os
import sys
import requests
import time

def check_health():
    """Check if the monitoring service is healthy"""
    try:
        # Check if health endpoint is enabled
        enable_health = os.getenv('ENABLE_HEALTH_ENDPOINT', 'false').lower() == 'true'
        health_port = int(os.getenv('HEALTH_PORT', '8080'))
        
        if enable_health:
            # Try to connect to health endpoint
            response = requests.get(f'http://localhost:{health_port}/health', timeout=5)
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'healthy':
                    print("Health check passed: service is healthy")
                    return True
                else:
                    print(f"Health check failed: service status is {data.get('status')}")
                    return False
            else:
                print(f"Health check failed: HTTP {response.status_code}")
                return False
        else:
            # If health endpoint is disabled, check if monitor process is running
            # by looking for the main process (this is a simple check)
            # In a real container, we'd check if the Python process is responsive
            
            # Check if we can import the monitor module (basic sanity check)
            try:
                import monitor
                print("Health check passed: monitor module is importable")
                return True
            except ImportError as e:
                print(f"Health check failed: cannot import monitor module: {e}")
                return False
                
    except requests.exceptions.RequestException as e:
        print(f"Health check failed: cannot connect to health endpoint: {e}")
        return False
    except Exception as e:
        print(f"Health check failed: unexpected error: {e}")
        return False

if __name__ == "__main__":
    if check_health():
        sys.exit(0)
    else:
        sys.exit(1)