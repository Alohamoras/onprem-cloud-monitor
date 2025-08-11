# Infrastructure Templates

This directory contains Infrastructure as Code templates for deploying the CloudWatch Synthetics monitoring solution.

## CloudFormation

- `cloudformation/` - CloudFormation templates for AWS resource deployment
- `cloudformation/main-template.yaml` - Main template with all resources
- `cloudformation/parameters/` - Parameter files for different environments

## CDK

- `cdk/` - AWS CDK TypeScript implementation
- `cdk/lib/` - CDK stack definitions and constructs
- `cdk/bin/` - CDK application entry points

## Deployment

Choose either CloudFormation or CDK for deployment based on your preference and requirements.