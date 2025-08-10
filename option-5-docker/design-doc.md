# Option 5: Docker Container Monitoring

## Overview

A lightweight Docker container that sends heartbeat metrics to AWS CloudWatch, providing monitoring for any environment that can run Docker containers.

## Architecture

```
Docker Container
├── Python Script (heartbeat sender)
├── AWS CLI / boto3
├── Configuration via environment variables
└── Health check endpoint (optional)
                ↓
        AWS CloudWatch Metrics
                ↓ 
        CloudWatch Alarms → SNS → Email/SMS
```

## Key Features

- **🐳 Container-based**: Deploy anywhere Docker runs
- **📊 CloudWatch integration**: Leverages AWS native monitoring
- **🔧 Environment-driven config**: All settings via environment variables
- **💡 Lightweight**: Minimal resource footprint
- **📈 Scalable**: Deploy multiple containers with unique identifiers
- **🔄 Health checks**: Built-in container health monitoring

## Container Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AWS_ACCESS_KEY_ID` | Yes | - | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | Yes | - | AWS secret key |
| `AWS_REGION` | Yes | us-east-1 | AWS region |
| `CONTAINER_NAME` | No | hostname | Unique identifier for this container |
| `HEARTBEAT_INTERVAL` | No | 300 | Seconds between heartbeats (5 minutes) |
| `CLOUDWATCH_NAMESPACE` | No | ContainerMonitoring/Heartbeat | CloudWatch namespace |
| `LOG_LEVEL` | No | INFO | Logging level (DEBUG, INFO, WARN, ERROR) |

### Optional Health Monitoring
| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ENABLE_HEALTH_ENDPOINT` | No | false | Enable HTTP health check endpoint |
| `HEALTH_PORT` | No | 8080 | Port for health check endpoint |
| `MONITOR_TARGETS` | No | - | Comma-separated list of IPs/hosts to monitor |
| `TARGET_PORT` | No | 80 | Port to check on monitor targets |

## Deployment Examples

### Basic Heartbeat Container
```bash
docker run -d \
  --name monitoring-container \
  --restart unless-stopped \
  -e AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE \
  -e AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY \
  -e AWS_REGION=us-east-1 \
  -e CONTAINER_NAME=production-server-1 \
  -e HEARTBEAT_INTERVAL=120 \
  onprem-monitor:latest
```

### With Target Monitoring
```bash
docker run -d \
  --name monitoring-container \
  --restart unless-stopped \
  -e AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE \
  -e AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY \
  -e AWS_REGION=us-east-1 \
  -e CONTAINER_NAME=snowball-monitor-1 \
  -e MONITOR_TARGETS=10.0.1.100,10.0.1.101 \
  -e TARGET_PORT=8443 \
  -e ENABLE_HEALTH_ENDPOINT=true \
  -p 8080:8080 \
  onprem-monitor:latest
```

### Docker Compose
```yaml
version: '3.8'
services:
  monitor:
    image: onprem-monitor:latest
    container_name: onprem-monitor
    restart: unless-stopped
    environment:
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_REGION=us-east-1
      - CONTAINER_NAME=location-datacenter-1
      - HEARTBEAT_INTERVAL=300
      - MONITOR_TARGETS=10.0.1.100,10.0.1.101,10.0.1.102
      - TARGET_PORT=8443
      - ENABLE_HEALTH_ENDPOINT=true
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## CloudWatch Metrics

The container will send these metrics:

### Heartbeat Metrics
- `ContainerHeartbeat` (Value: 1, Unit: Count)
  - Dimensions: ContainerName, Region
- `ContainerUptime` (Value: seconds, Unit: Seconds)
  - Dimensions: ContainerName, Region

### Target Monitoring Metrics (if enabled)
- `TargetStatus` (Value: 1=online, 0=offline, Unit: Count)
  - Dimensions: ContainerName, TargetIP, TargetPort
- `TargetResponseTime` (Value: milliseconds, Unit: Milliseconds)
  - Dimensions: ContainerName, TargetIP, TargetPort

## CloudWatch Alarms

### Container Heartbeat Alarm
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "Container-Heartbeat-Lost-${CONTAINER_NAME}" \
  --alarm-description "Container heartbeat lost for ${CONTAINER_NAME}" \
  --metric-name ContainerHeartbeat \
  --namespace ContainerMonitoring/Heartbeat \
  --statistic Sum \
  --period 600 \
  --threshold 0.5 \
  --comparison-operator LessThanThreshold \
  --datapoints-to-alarm 2 \
  --evaluation-periods 2 \
  --treat-missing-data breaching \
  --dimensions Name=ContainerName,Value=${CONTAINER_NAME} \
  --alarm-actions ${SNS_TOPIC_ARN}
```

### Target Monitoring Alarm (if targets configured)
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "Container-Target-Offline-${CONTAINER_NAME}" \
  --alarm-description "Monitored target offline for ${CONTAINER_NAME}" \
  --metric-name TargetStatus \
  --namespace ContainerMonitoring/Heartbeat \
  --statistic Average \
  --period 300 \
  --threshold 0.5 \
  --comparison-operator LessThanThreshold \
  --datapoints-to-alarm 2 \
  --evaluation-periods 2 \
  --treat-missing-data breaching \
  --dimensions Name=ContainerName,Value=${CONTAINER_NAME} \
  --alarm-actions ${SNS_TOPIC_ARN}
```

## Use Cases

### 1. Simple Container Heartbeat
- Deploy container in any environment
- Sends "I'm alive" signals to CloudWatch
- Get alerted if container stops/crashes

### 2. Infrastructure Monitoring
- Monitor specific devices/services from the container
- Combines container heartbeat + target monitoring
- Single container can monitor multiple targets

### 3. Multi-Location Deployment
- Deploy identical containers across locations
- Each with unique `CONTAINER_NAME`
- Centralized monitoring in AWS CloudWatch

### 4. Kubernetes/Orchestrated Deployments
- Deploy as Kubernetes DaemonSet or Deployment
- Use ConfigMaps/Secrets for AWS credentials
- Leverage Kubernetes health checks

## Benefits vs Other Options

| Feature | Docker Container | EC2 Instance | Lambda | SSM Agent |
|---------|-----------------|--------------|---------|-----------|
| **Deployment** | Any Docker environment | AWS only | AWS only | VM required |
| **Cost** | ~$0.30/month metrics | ~$5/month | ~$1-16/month | ~$15-30/month |
| **Complexity** | Low | Low | Medium | Medium |
| **Portability** | High | Low | None | Medium |
| **Resource Usage** | Minimal | Low | None (serverless) | Medium |
| **Debugging** | Easy | Easy | Hard | Medium |

## Implementation Considerations

### Security
- Use IAM roles with minimal permissions
- Consider AWS Secrets Manager for credentials
- Network isolation in container orchestration

### Monitoring the Monitor
- Container health checks
- Log aggregation (stdout/stderr)
- Resource usage monitoring

### Scalability
- Multiple containers per location
- Load balancing for health endpoints
- Centralized configuration management

This Docker option provides maximum flexibility while maintaining the simplicity of the existing bash script approach, making it perfect for hybrid cloud environments.