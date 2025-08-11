#!/bin/bash

# Example deployment script showing different deployment scenarios
# This script demonstrates how to deploy the CDK stack with various configurations

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}CloudWatch Synthetics CDK Deployment Examples${NC}\n"

# Example 1: Development Environment
echo -e "${GREEN}Example 1: Development Environment Deployment${NC}"
echo "This example deploys a basic monitoring setup for development"
echo ""
echo "Command:"
echo "./scripts/deploy.sh --environment dev --context examples/dev-config.json"
echo ""
echo "This will create:"
echo "- 2 basic canaries (heartbeat + API)"
echo "- Standard alarms with email notifications"
echo "- 7-day artifact retention"
echo "- 5-minute monitoring frequency"
echo ""

# Example 2: Production Environment
echo -e "${GREEN}Example 2: Production Environment Deployment${NC}"
echo "This example deploys a comprehensive monitoring setup for production"
echo ""
echo "Command:"
echo "./scripts/deploy.sh --environment prod --context examples/prod-config.json"
echo ""
echo "This will create:"
echo "- 6 canaries (heartbeat + API + 4 additional targets)"
echo "- Comprehensive alarms with escalation"
echo "- Email + Slack notifications"
echo "- 30-day artifact retention"
echo "- 2-minute monitoring frequency"
echo ""

# Example 3: Custom Configuration
echo -e "${GREEN}Example 3: Custom Configuration via Environment Variables${NC}"
echo "This example shows deployment using environment variables"
echo ""
echo "Commands:"
cat << 'EOF'
export VPC_ID="vpc-12345678"
export SUBNET_IDS="subnet-12345678,subnet-87654321"
export NOTIFICATION_EMAIL="alerts@company.com"
export TARGET_ENDPOINT="10.1.1.100"
export CANARY_NAME="custom-monitor"
export MONITORING_FREQUENCY="rate(10 minutes)"

./scripts/deploy.sh --environment dev
EOF
echo ""

# Example 4: Cost Estimation
echo -e "${GREEN}Example 4: Cost Estimation${NC}"
echo "This example shows how to estimate costs before deployment"
echo ""
echo "Commands:"
echo "cd scripts"
echo "ts-node cost-estimate.ts ../examples/dev-config.json"
echo "ts-node cost-estimate.ts ../examples/prod-config.json"
echo ""

# Example 5: Deployment with Diff
echo -e "${GREEN}Example 5: Review Changes Before Deployment${NC}"
echo "This example shows how to review changes before deploying"
echo ""
echo "Command:"
echo "./scripts/deploy.sh --diff --context examples/prod-config.json"
echo ""

# Example 6: Destroy Stack
echo -e "${GREEN}Example 6: Clean Up / Destroy Stack${NC}"
echo "This example shows how to destroy the deployed stack"
echo ""
echo "Command:"
echo "./scripts/deploy.sh --destroy --environment dev"
echo ""

# Example 7: Multi-Region Deployment
echo -e "${GREEN}Example 7: Multi-Region Deployment${NC}"
echo "This example shows deployment to multiple regions"
echo ""
echo "Commands:"
cat << 'EOF'
# Deploy to us-east-1
./scripts/deploy.sh --environment prod --region us-east-1 --context examples/prod-config.json

# Deploy to eu-west-1
./scripts/deploy.sh --environment prod --region eu-west-1 --context examples/prod-config.json
EOF
echo ""

# Example 8: Using AWS Profiles
echo -e "${GREEN}Example 8: Using AWS Profiles${NC}"
echo "This example shows deployment using specific AWS profiles"
echo ""
echo "Commands:"
cat << 'EOF'
# Deploy using production AWS profile
./scripts/deploy.sh --environment prod --profile production --context examples/prod-config.json

# Deploy using development AWS profile
./scripts/deploy.sh --environment dev --profile development --context examples/dev-config.json
EOF
echo ""

# Prerequisites Check
echo -e "${YELLOW}Prerequisites Check:${NC}"
echo ""
echo "Before running these examples, ensure you have:"
echo "1. AWS CLI configured with appropriate credentials"
echo "2. Node.js 18.x or later installed"
echo "3. AWS CDK installed globally: npm install -g aws-cdk"
echo "4. jq installed for JSON processing"
echo "5. Proper VPC and subnet configuration in AWS"
echo ""

# Configuration Tips
echo -e "${YELLOW}Configuration Tips:${NC}"
echo ""
echo "1. Update VPC and subnet IDs in configuration files"
echo "2. Ensure on-premises CIDR blocks are correct"
echo "3. Verify target endpoints are accessible from VPC"
echo "4. Test email addresses for notifications"
echo "5. Configure Slack webhook URLs if using Slack integration"
echo ""

# Cost Considerations
echo -e "${YELLOW}Cost Considerations:${NC}"
echo ""
echo "Estimated monthly costs (varies by region and usage):"
echo "- Development setup: $15-25/month"
echo "- Production setup: $45-75/month"
echo ""
echo "Use the cost estimation script for accurate estimates:"
echo "ts-node scripts/cost-estimate.ts examples/your-config.json"
echo ""

echo -e "${BLUE}Ready to deploy? Choose an example above and run the corresponding command!${NC}"