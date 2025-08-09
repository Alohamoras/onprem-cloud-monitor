# On-Premises System Monitor

A simple, reliable monitoring solution for AWS customers who need immediate alerts when their on-premises infrastructure goes offline. Get notified within minutes of outages due to power failures, hardware issues, or network problems.

## Quick Overview

This project provides **four different approaches** to monitor your on-premises systems, each designed for different scenarios and technical requirements. All solutions focus on simplicity, reliability, and cost-effectiveness.

### Core Features
- ✅ **Real-time connectivity monitoring** - Know within minutes when systems go offline
- ✅ **Intelligent alerting** - Only get notified when status actually changes, not on every check
- ✅ **Multiple deployment options** - Choose the approach that fits your infrastructure and skills
- ✅ **Cost-effective** - Solutions range from $5-50/month regardless of how many locations you monitor
- ✅ **Production-ready** - Includes logging, error handling, and health monitoring

## Perfect For
- **AWS customers** with on-premises locations needing uptime monitoring
- **System administrators** who want immediate outage notifications  
- **Teams** managing distributed infrastructure on a budget
- **Organizations** valuing simplicity over complex monitoring platforms

## Monitoring Approaches
We provide four different implementation options, each with distinct advantages:

### Option 1: SSM Hybrid Agents
**Best for:** Organizations already using AWS Systems Manager

- **How it works:** CloudWatch agent on on-premises VM with SSM hybrid activation
- **Cost:** ~$15-30/month
- **Complexity:** Medium - requires SSM hybrid setup
- **Pros:** Lowest code solution, remote access capabilities
- **Cons:** More initial setup, requires on-premises VM, could be difficult to scale

[📖 View SSM Documentation](./option-3-ssm-agents/README.md)

### Option 2: Lambda Serverless
**Best for:** Cost optimization and serverless-first organizations

- **How it works:** Python Lambda function triggered by EventBridge
- **Cost:** ~$1-16/month (depending on network setup)
- **Complexity:** Medium - requires VPC networking knowledge
- **Pros:** No servers to manage, scales automatically
- **Cons:** VPC networking complexity, cold start delays

[📖 View Lambda Documentation](./option-2-serverless/lamda-deployment-guide.md)

### Option 3: EC2 + Bash Script
**Best for:** Most users, especially those new to AWS monitoring

- **How it works:** Simple bash script running on a small EC2 instance
- **Cost:** ~$5/month
- **Complexity:** Low - just bash, netcat, and AWS CLI
- **Pros:** Easy to understand, debug and modify, one 
- **Cons:** Requires managing an EC2 instance

[📖 View EC2 Documentation](./option-1-ec2-bash/README.md)

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