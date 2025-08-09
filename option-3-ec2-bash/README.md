# AWS Snowball Device Monitor

A lightweight, automated monitoring solution for AWS Snowball devices that provides real-time connectivity monitoring, alerting, and health tracking.  This solution is designed for environments where your aws cloud environment has connectivity to your snow device. 

See the Deployment-Guide.md for setup instructions.

## What This Does

This project monitors the health and connectivity of AWS Snowball devices by periodically testing network connectivity and sending status updates to AWS CloudWatch. When a Snowball device becomes unreachable, the system automatically sends alerts via SNS, helping you quickly identify and respond to connectivity issues.

## How It Works

**Core Monitoring Process:**
1. **Connectivity Testing** - A bash script runs at regular intervals (every 1-5 minutes) to test network connectivity to your Snowball device using netcat
2. **Metrics Collection** - Results are sent to AWS CloudWatch as custom metrics (1 = online, 0 = offline)
3. **Intelligent Alerting** - CloudWatch alarms detect state changes and trigger SNS notifications only when status actually changes
4. **Health Monitoring** - Built-in health checks ensure the monitoring system itself is working properly

**Key Features:**
- ✅ **Self-monitoring** - Includes health checks to ensure the monitor itself is running
- ✅ **Cost-effective** - Runs on a t3.nano instance (~$5/month total cost)
- ✅ **Production-ready** - Includes logging, error handling, and maintenance scripts
- ✅ **AWS-native** - Uses CloudWatch alarms for sophisticated alerting logic

## Use Cases
- **Data Migration Projects** - Monitor Snowball devices during large data transfers
- **Remote Locations** - Get instant alerts when devices at remote sites go offline
- **Compliance Requirements** - Maintain audit logs of device availability
- **Proactive Operations** - Detect connectivity issues before they impact your workflow

## Architecture

```
Snowball Device  ← [Network Test] ← EC2 Instance
                                                      ↓
CloudWatch Metrics ← [Status: 1=Online, 0=Offline] ←
        ↓
CloudWatch Alarms → SNS Topic → Email/SMS/Slack Alerts
```

The system is designed to be simple, reliable, and maintainable while providing enterprise-grade monitoring capabilities.

## Monthly Costs Estimate

- **t3.nano instance**: ~$3.50/month (24/7)
- **EBS storage (8GB)**: ~$0.80/month  
- **CloudWatch logs**: ~$0.50/month
- **Data transfer**: ~$0.10/month
- **Total**: ~$4.90/month

## FAQ

### **Q: What other architectures did you consider for this solution?**

**A:** I evaluated several AWS-native approaches before settling on EC2:

**CloudWatch Synthetics**: Limited to HTTP/HTTPS checks, couldn't monitor raw TCP port 8443 on private IP (It might be possible but have not got it working yet)

**Lambda + VPC**: VPC routing complexity proved challenging in my environment

**Why EC2 Won:**
- Direct private network access without VPC complexity
- Easy debugging and tool installation
- Predictable costs (~$5/month vs variable Lambda costs)
- Future extensibility for additional monitoring features

### **Q: How does this scale for multiple Snowball devices?**

**A:** 
- **1-10 devices**: Modify script to loop through multiple IPs on same instance
- **10+ devices**: Potentially deploy multiple instances per region/network segment or scale up instance  
- **50+ devices**: Consider migrating to Lambda + Step Functions architecture

### **Q: What happens if the EC2 instance goes down?**

**A:** 
- CloudWatch alarm can treat missing data as "breaching" and triggers alerts
- Health check script can be monitored externally
- Can enable EC2 auto-recovery for hardware failures
- Future enhancement: secondary monitoring instance or Lambda watchdog

### **Q: Can this be deployed on-premises?**

**A:** Yes! Replace AWS services with local alternatives:
- CloudWatch → Prometheus/InfluxDB  
- SNS → Email/Slack webhooks
- CloudWatch Logs → Local log aggregation
- Runs on any Linux system with bash, netcat, and network access

### **Q: What's your roadmap for future enhancements?**

**A:** 
- **Short-term**: Performance metrics, dashboard
- **Medium-term**: Lambda + Step Functions version, Systems Manager integration  
- **Long-term**: Full AWS storage monitoring suite, Terraform modules
