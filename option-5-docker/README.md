# Option 5: Docker Container Monitor

A lightweight Docker container that sends heartbeat metrics to AWS CloudWatch, providing monitoring for any environment that can run Docker containers.

## Features

- 🐳 **Container-based**: Deploy anywhere Docker runs
- 📊 **CloudWatch integration**: Leverages AWS native monitoring  
- 🔧 **Environment-driven config**: All settings via environment variables
- 💡 **Lightweight**: Minimal resource footprint (~50MB image, <50MB RAM)
- 📈 **Scalable**: Deploy multiple containers with unique identifiers
- 🔄 **Health checks**: Built-in container health monitoring
- 🎯 **Target monitoring**: Optional monitoring of external devices/services
- 📋 **Metrics endpoint**: Prometheus-compatible metrics (optional)

## Quick Start

### 1. Clone and Build

```bash
git clone <repository>
cd option-5-docker-container
chmod +x build.sh setup-alarms.sh
./build.sh
```

### 2. Configure Environment

```bash
cp .env.example .env
# Edit .env with your AWS credentials and settings
```

### 3. Deploy

```bash
# Option A: Docker Compose (recommended)
docker-compose up -d

# Option B: Direct Docker run
docker run -d --restart unless-stopped \
  --name onprem-monitor \
  -e AWS_ACCESS_KEY_ID=your_key \
  -e AWS_SECRET_ACCESS_KEY=your_secret \
  -e AWS_REGION=us-east-1 \
  -e CONTAINER_NAME=datacenter-1 \
  onprem-monitor:latest
```

### 4. Setup CloudWatch Alarms

```bash
export CONTAINER_NAME=datacenter-1
export SNS_TOPIC_ARN=arn:aws:sns:us-east-1:123456789012:alerts
./setup-alarms.sh
```

## Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | `wJalrXUt...` |
| `AWS_REGION` | AWS region | `us-east-1` |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTAINER_NAME` | hostname | Unique identifier for this container |
| `HEARTBEAT_INTERVAL` | 300 | Seconds between heartbeats |
| `CLOUDWATCH_NAMESPACE` | ContainerMonitoring/Heartbeat | CloudWatch namespace |
| `LOG_LEVEL` | INFO | Logging level (DEBUG, INFO, WARN, ERROR) |
| `ENABLE_HEALTH_ENDPOINT` | false | Enable HTTP health check endpoint |
| `HEALTH_PORT` | 8080 | Port for health check endpoint |
| `MONITOR_TARGETS` | - | Comma-separated IPs to monitor |
| `TARGET_PORT` | 80 | Port to check on target hosts |
| `TARGET_TIMEOUT` | 5 | Timeout for target checks (seconds) |

## Use Cases

### 1. Simple Heartbeat Monitoring

Monitor container uptime and get alerted if it stops:

```bash
docker run -d --restart unless-stopped \
  --name datacenter-monitor \
  -e AWS_ACCESS_KEY_ID=your_key \
  -e AWS_SECRET_ACCESS_KEY=your_secret \
  -e AWS_REGION=us-east-1 \
  -e CONTAINER_NAME=datacenter-1 \
  -e HEARTBEAT_INTERVAL=120 \
  onprem-monitor:latest
```

### 2. Infrastructure Device Monitoring

Monitor Snowball devices or other infrastructure:

```bash
docker run -d --restart unless-stopped \
  --name snowball-monitor \
  -e AWS_ACCESS_KEY_ID=your_key \
  -e AWS_SECRET_ACCESS_KEY=your_secret \
  -e AWS_REGION=us-east-1 \
  -e CONTAINER_NAME=snowball-site-1 \
  -e MONITOR_TARGETS=10.0.1.100,10.0.1.101,10.0.1.102 \
  -e TARGET_PORT=8443 \
  -e ENABLE_HEALTH_ENDPOINT=true \
  -p 8080:8080 \
  onprem-monitor:latest
```

### 3. Multi-Location Deployment

Deploy across multiple locations with unique names:

```bash
# Location 1
docker run -d --name monitor-nyc \
  -e CONTAINER_NAME=nyc-datacenter \
  ... other config ...

# Location 2  
docker run -d --name monitor-la \
  -e CONTAINER_NAME=la-datacenter \
  ... other config ...
```

### 4. Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: onprem-monitor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: onprem-monitor
  template:
    metadata:
      labels:
        app: onprem-monitor
    spec:
      containers:
      - name: monitor
        image: onprem-monitor:latest
        env:
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: aws-credentials
              key: access-key-id
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: aws-credentials
              key: secret-access-key
        - name: AWS_REGION
          value: "us-east-1"
        - name: CONTAINER_NAME
          value: "k8s-cluster-1"
        - name: ENABLE_HEALTH_ENDPOINT
          value: "true"
        ports:
        - containerPort: 8080
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 30
```

## CloudWatch Metrics

The container sends these metrics to CloudWatch:

### Heartbeat Metrics
- **ContainerHeartbeat**: Always 1 when container is running
  - Dimensions: ContainerName, Region
- **ContainerUptime**: Container uptime in seconds
  - Dimensions: ContainerName, Region

### Target Monitoring Metrics (if enabled)
- **TargetStatus**: 1 if target is online, 0 if offline
  - Dimensions: ContainerName, TargetIP, TargetPort
- **TargetResponseTime**: Response time in milliseconds
  - Dimensions: ContainerName, TargetIP, TargetPort

## CloudWatch Alarms

The `setup-alarms.sh` script creates these alarms:

### Container Heartbeat Alarm
- **Trigger**: No heartbeat for 10 minutes
- **Action**: Send SNS notification
- **Use**: Detects when container stops or crashes

### Target Monitoring Alarm
- **Trigger**: Monitored targets offline for 5 minutes  
- **Action**: Send SNS notification
- **Use**: Detects when external devices/services fail

## Health Endpoint

When `ENABLE_HEALTH_ENDPOINT=true`, the container exposes HTTP endpoints:

### Health Check
```bash
curl http://localhost:8080/health
```

Response:
```json
{
  "status": "healthy",
  "container_name": "datacenter-1",
  "uptime_seconds": 3600.5,
  "last_heartbeat": "2024-01-15T10:30:00Z",
  "target_status": {
    "10.0.1.100": {
      "online": true,
      "response_time": 45.2,
      "last_check": "2024-01-15T10:29:55Z"
    }
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Prometheus Metrics
```bash
curl http://localhost:8080/metrics
```

Response:
```
container_heartbeat{container_name="datacenter-1"} 1
container_uptime_seconds{container_name="datacenter-1"} 3600.5
target_status{container_name="datacenter-1",target="10.0.1.100"} 1
target_response_time_ms{container_name="datacenter-1",target="10.0.1.100"} 45.2
```

## Security

### Best Practices
- **IAM Roles**: Use IAM roles instead of access keys when possible
- **Secrets Management**: Use Docker secrets or Kubernetes secrets for credentials
- **Network Security**: Run containers in isolated networks
- **Least Privilege**: Grant minimal CloudWatch permissions

### Required AWS Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    }
  ]
}
```

## Monitoring

### Container Logs
```bash
# View logs
docker logs -f onprem-monitor

# Follow logs with timestamps
docker logs -f --timestamps onprem-monitor
```

### Container Health
```bash
# Check container status
docker ps -f name=onprem-monitor

# Check health status
docker inspect onprem-monitor | grep -A5 Health

# Manual health check
docker exec onprem-monitor python health_check.py
```

### AWS CloudWatch
- **Metrics**: ContainerMonitoring/Heartbeat namespace
- **Logs**: Container logs via CloudWatch Logs (optional)
- **Alarms**: Monitor container and target health

## Troubleshooting

### Container Won't Start
```bash
# Check logs for errors
docker logs onprem-monitor

# Common issues:
# - Invalid AWS credentials
# - Network connectivity issues
# - Invalid environment variables
```

### No Metrics in CloudWatch
```bash
# Check AWS credentials
docker exec onprem-monitor aws sts get-caller-identity

# Check CloudWatch permissions
docker exec onprem-monitor aws cloudwatch list-metrics --max-items 1

# Verify network connectivity
docker exec onprem-monitor curl -I https://monitoring.us-east-1.amazonaws.com
```

### Health Endpoint Not Working
```bash
# Check if health endpoint is enabled
docker exec onprem-monitor printenv | grep HEALTH

# Test health endpoint
curl http://localhost:8080/health

# Check port mapping
docker port onprem-monitor
```

## Cost Analysis

### Monthly Costs

| Component | Cost | Notes |
|-----------|------|-------|
| **Container Resources** | $0 | Runs on existing infrastructure |
| **CloudWatch Custom Metrics** | ~$0.30 | ~4,320 metrics/month |
| **CloudWatch Alarms** | ~$0.20 | 2 alarms |
| **SNS Notifications** | ~$0.01 | Assuming 10 alerts/month |
| **Data Transfer** | ~$0.01 | Minimal CloudWatch API calls |
| **Total** | **~$0.52/month** | **Per container** |

### Scaling Costs
- **1-10 containers**: ~$5/month
- **10-50 containers**: ~$25/month  
- **50-100 containers**: ~$50/month

### Cost Comparison

| Option | Monthly Cost | Complexity | Portability |
|--------|--------------|------------|-------------|
| **Docker Container** | **$0.52** | Low | High |
| Lambda + VPC Endpoints | $16.50 | Medium | Low |
| EC2 + Bash Script | $5.00 | Low | Low |
| SSM Hybrid Agents | $15-30 | Medium | Medium |

## Integration Examples

### With Existing Monitoring

```bash
# Export metrics to external monitoring
docker run -d \
  --name monitor-with-export \
  -e ENABLE_HEALTH_ENDPOINT=true \
  -p 8080:8080 \
  ... other config ...

# Scrape metrics with Prometheus
# Add to prometheus.yml:
# - targets: ['localhost:8080']
```

### With Log Aggregation

```yaml
version: '3.8'
services:
  monitor:
    image: onprem-monitor:latest
    logging:
      driver: "fluentd"
      options:
        fluentd-address: localhost:24224
        tag: monitor.container
```

### With Service Discovery

```bash
# Register with Consul
docker run -d \
  --name monitor-consul \
  -e CONTAINER_NAME=consul-node-1 \
  ... other config ...
  
# Container automatically registers heartbeat
# Consul can health check the /health endpoint
```

## Advanced Configuration

### Custom Namespace Patterns
```bash
# Environment-based namespacing
-e CLOUDWATCH_NAMESPACE=Production/ContainerMonitoring/Heartbeat

# Location-based namespacing  
-e CLOUDWATCH_NAMESPACE=Datacenter/NYC/Monitoring

# Application-based namespacing
-e CLOUDWATCH_NAMESPACE=Application/Snowball/Monitoring
```

### Multi-Target Monitoring
```bash
# Monitor different device types
-e MONITOR_TARGETS=10.0.1.100:8443,10.0.1.200:22,10.0.1.300:80
-e TARGET_TIMEOUT=10
```

### Development vs Production
```bash
# Development
-e LOG_LEVEL=DEBUG
-e HEARTBEAT_INTERVAL=60
-e ENABLE_HEALTH_ENDPOINT=true

# Production  
-e LOG_LEVEL=INFO
-e HEARTBEAT_INTERVAL=300
-e ENABLE_HEALTH_ENDPOINT=false
```

This Docker container option provides maximum flexibility and portability while maintaining the simplicity of the bash script approach, making it perfect for modern containerized environments and hybrid cloud deployments.