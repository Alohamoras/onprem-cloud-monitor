# On-Premises System Monitor

I wanted a solution to monitor my on-prem server and the connection to the AWS cloud.  If either goes down I want an email alert.  There a lot of solutions out there for this, I wanted something as simple and reliable as possible.  There are many options for how to achomplish this and trade offs to consider.

A simple, reliable monitoring solution that helps AWS customers keep track of critical systems at remote locations. When your on-premises infrastructure goes down due to power outages, hardware failures, or network issues, you need to know immediately - not hours later when someone notices.

## The Problem We Solve

**Remote locations are hard to monitor.** Whether you're running edge computing, retail locations, manufacturing sites, or field offices, system outages at remote sites can go undetected for hours. By the time someone notices, you've lost valuable time, data, or revenue.

**Traditional monitoring is complex.** Most monitoring solutions require extensive setup, ongoing maintenance, and specialized knowledge. When you have dozens or hundreds of remote locations, complexity becomes your enemy.

**You need alerts that actually work.** Simple ping checks aren't enough. You need intelligent monitoring that can distinguish between temporary network blips and real outages, with alerts that reach the right people through the channels they actually use.

## Our Solution

This project provides **four different approaches** to monitor your on-premises systems, each designed for different scenarios and technical requirements. All solutions focus on simplicity, reliability, and cost-effectiveness.

### Core Features
- ✅ **Real-time connectivity monitoring** - Know within minutes when systems go offline
- ✅ **Intelligent alerting** - Only get notified when status actually changes, not on every check
- ✅ **Multiple deployment options** - Choose the approach that fits your infrastructure and skills
- ✅ **Cost-effective** - Solutions range from $5-50/month regardless of how many locations you monitor
- ✅ **Production-ready** - Includes logging, error handling, and health monitoring

## Who This Is For

- **AWS customers** with on-premises locations connected to the cloud
- **System administrators** who need immediate notification of outages
- **DevOps teams** managing distributed infrastructure
- **Business stakeholders** who want visibility into remote site availability
- **Anyone** who values simplicity over complexity in monitoring solutions

## Monitoring Approaches

We provide four different implementation options, each with distinct advantages:

### Option 1: EC2 + Bash Script
**Best for:** Most users, especially those new to AWS monitoring

- **How it works:** Simple bash script running on a small EC2 instance
- **Cost:** ~$5/month
- **Complexity:** Low - just bash, netcat, and AWS CLI
- **Pros:** Easy to understand, debug, and modify
- **Cons:** Requires managing an EC2 instance

[📖 View EC2 Documentation](./option-1-ec2-bash/README.md)

### Option 2: Lambda Serverless
**Best for:** Cost optimization and serverless-first organizations

- **How it works:** Python Lambda function triggered by EventBridge
- **Cost:** ~$1-16/month (depending on network setup)
- **Complexity:** Medium - requires VPC networking knowledge
- **Pros:** No servers to manage, scales automatically
- **Cons:** VPC networking complexity, cold start delays

[📖 View Lambda Documentation](./option-2-serverless/lamda-deployment-guide.md)

### Option 3: SSM Hybrid Agents
**Best for:** Organizations already using AWS Systems Manager

- **How it works:** CloudWatch agent on on-premises VM with SSM hybrid activation
- **Cost:** ~$15-30/month
- **Complexity:** Medium - requires SSM hybrid setup
- **Pros:** Lowest code solution, remote access capabilities
- **Cons:** More initial setup, requires on-premises VM

[📖 View SSM Documentation](./option-3-ssm-agents/README.md)

### Option 4: On-Premises Only
**Best for:** Air-gapped environments or locations without reliable cloud connectivity

- **How it works:** Standalone script using SMTP for email alerts
- **Cost:** Free (just email service costs)
- **Complexity:** Low - runs entirely on-premises
- **Pros:** No cloud dependencies, works in any environment
- **Cons:** Limited to email alerts, no cloud integration

[📖 View On-Premises Documentation](./option-4-on-prem-only/README.md)

## Quick Start

1. **Choose your approach** based on your infrastructure and requirements
2. **Follow the specific documentation** for your chosen option
3. **Configure your device IPs** and alert destinations
4. **Test the monitoring** by simulating an outage
5. **Set up dashboards** (optional) for ongoing visibility

## Architecture Overview

All cloud-connected options (1-3) follow this general pattern:

```
On-Premises System  ← [Network Test] ← Monitoring Component
                                                      ↓
CloudWatch Metrics  ← [Status: 1=Online, 0=Offline] ←
        ↓
CloudWatch Alarms → SNS Topic → Email/SMS/Slack Alerts
```

Option 4 uses direct SMTP for simpler, cloud-independent alerting.

## Use Cases

- **Retail locations** - Monitor point-of-sale systems and network connectivity
- **Manufacturing sites** - Track critical equipment and production systems
- **Edge computing** - Ensure remote compute resources stay online
- **Field offices** - Monitor essential business systems and connectivity
- **IoT deployments** - Keep track of edge gateways and data collection points
- **Disaster recovery** - Monitor backup sites and failover systems

## Why We Built This

Existing monitoring solutions are either too complex (requiring dedicated teams) or too simple (just basic ping checks). We wanted something that:

- **Just works** - Minimal setup, maximum reliability
- **Scales simply** - Add new locations without architectural changes
- **Costs little** - Monitoring shouldn't break your budget
- **Alerts smartly** - Only notify when action is needed
- **Fits your skills** - Choose the approach that matches your team's expertise

## Getting Help

- **Issues or questions?** Open a GitHub issue
- **Feature requests?** We'd love to hear your ideas
- **Success stories?** Share how you're using this solution

## What's Next

This project started focused on AWS Snowball devices but has evolved into a general-purpose on-premises monitoring solution. We're continuously improving based on real-world usage and feedback.

**Planned enhancements:**
- Terraform modules for automated deployment
- Additional alert channels (Slack, Teams, PagerDuty)
- Performance metrics and dashboards
- Multi-region deployment guides

---

*Simple monitoring for complex infrastructure. Because knowing is better than guessing.*