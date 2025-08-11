# TODO List

## Content Updates & Refactoring

- [ ] **Scrub snowball references across the repo** 
  - Make it a more general on-prem monitoring guide
  - Update terminology to be cloud-agnostic
  - Review all documentation and code comments
  - _Note: Will create separate project for general on-prem monitoring theme_

## Testing & Validation

- [ ] **Test the SSM agents workflows**
  - Validate installation scripts
  - Test monitoring functionality
  - Document any issues or improvements needed

## Lambda Deployment (Option 2)

- [ ] **Complete lambda deployment guide end-to-end**
  - Remove assumptions from option 1 manual deployment
  - Create standalone, complete instructions
  - Add missing configuration steps

- [ ] **Create automated build script for lambda deployment**
  - Consider CloudFormation or CDK for cloud-native solution
  - Automate packaging and deployment process
  - Include dependency management
  - Add error handling and validation

## On-Premises Only Implementation (Option 4)

- [ ] **Complete on-prem only script**
  - Implement monitoring functionality
  - Add configuration options
  - Include error handling

- [ ] **Write comprehensive README for on-prem option**
  - Installation instructions
  - Configuration guide
  - Troubleshooting section

## Documentation

- [ ] **Update overall README**
  - Reflect new general monitoring focus
  - Update project description and goals
  - Revise option descriptions

- [ ] **Create hybrid monitoring high-level document**
  - Focus on strategic/architectural guidance
  - Discuss architectural patterns
  - Compare different deployment options
  - Could evolve into blog post content
  - Include best practices and considerations
  - _Location: docs/ folder_

## CloudWatch Canary Synthetics Implementation (Option 6)

- [ ] **Create CloudWatch Canary Synthetics option**
  - Design synthetic monitoring solution using CloudWatch Synthetics
  - Configure canaries to ping on-premises devices/endpoints
  - Set up CloudWatch alarms based on canary results
  - Include heartbeat and API canary examples
  - Document network connectivity requirements (VPC/VPN setup)
  - Add cost considerations and monitoring frequency recommendations

- [ ] **Create deployment automation for canaries**
  - CloudFormation/CDK templates for canary creation
  - Automated alarm configuration
  - Include IAM roles and permissions setup
  - Add canary script examples (Node.js/Python)

- [ ] **Write comprehensive guide for synthetics option**
  - Compare with other monitoring approaches
  - Network architecture considerations
  - Troubleshooting synthetic test failures
  - Best practices for canary configuration

## Future Considerations

- [ ] Consider adding CI/CD examples
- [ ] Evaluate additional monitoring targets
- [ ] Review security best practices documentation