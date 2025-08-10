# Lambda Option TODO List

## High Priority - Core Functionality

### 1. Code Cleanup & Standardization ✅ COMPLETED
- [x] **Rename files for consistency**
  - `snowball-monitor.py` → `on-prem-monitor.py` 
  - Update deployment guide references
- [x] **Remove Snowball-specific terminology**
  - Update variable names (SNOWBALL_DEVICES → TARGET_DEVICES)
  - Update comments and logging messages
  - Update CloudWatch namespace (Snowball/MultiDevice → OnPrem/MultiDevice)
- [x] **Add environment variable support**
  - Make device IPs configurable via environment variables
  - Add port and timeout configuration
  - Add CloudWatch namespace configuration

### 2. Deployment Guide Fixes ✅ COMPLETED
- [x] **Fix file reference inconsistencies**
  - Guide references "snowball-monitor-lambda.py" but file is "snowball-monitor.py"
  - Update all file paths and names
- [x] **Remove dependencies on Option 1**
  - Guide assumes SNS topic exists from manual deployment
  - Create standalone SNS topic creation steps
- [x] **Fix typo in filename**
  - `lamda-deployment-guide.md` → `lambda-deployment-guide.md`
- [x] **Simplify network configuration**
  - Current guide is overly complex for VPC setup
  - Provide simpler default option
  - Move advanced networking to separate section

### 3. Create Automated Deployment Script ✅ COMPLETED
- [x] **Create `deploy.sh` script**
  - Single script to deploy entire solution
  - Include error handling and validation
  - Support for different AWS regions
  - Cleanup/rollback functionality
- [x] **Add configuration validation**
  - Check AWS credentials
  - Validate VPC/subnet configuration
  - Test network connectivity before deployment

## Medium Priority - User Experience

### 4. Testing & Validation
- [ ] **Create test script**
  - Validate Lambda function works
  - Test CloudWatch metrics
  - Test alarm notifications
- [ ] **Add monitoring dashboard**
  - CloudWatch dashboard template
  - Key metrics visualization
- [ ] **Improve error handling**
  - Better error messages in Lambda function
  - Retry logic for transient failures
  - Dead letter queue for failed executions

### 5. Documentation Improvements
- [ ] **Add troubleshooting section**
  - Common deployment issues
  - Network connectivity problems
  - Permission issues
- [ ] **Create quick start guide**
  - 5-minute setup for simple cases
  - Default configurations
- [ ] **Add cost calculator**
  - Interactive cost estimation
  - Different usage scenarios

## Low Priority - Enhancements

### 6. Advanced Features
- [ ] **Add Slack/Teams integration**
  - Alternative to email notifications
  - Rich message formatting
- [ ] **Add custom health checks**
  - HTTP endpoint monitoring
  - Service-specific checks
- [ ] **Add configuration management**
  - Parameter Store integration
  - Dynamic device list updates

### 7. Infrastructure as Code
- [ ] **Create CloudFormation template**
  - Complete infrastructure deployment
  - Parameter-driven configuration
- [ ] **Add Terraform module**
  - Alternative IaC option
  - Multi-cloud support preparation

## Immediate Next Steps (This Session)

### Phase 1: File Cleanup (15 minutes) ✅ COMPLETED
1. ✅ Fix filename typo in deployment guide
2. ✅ Rename Python files for consistency
3. ✅ Update all file references in documentation

### Phase 2: Code Updates (20 minutes) ✅ COMPLETED
1. ✅ Remove Snowball terminology from code
2. ✅ Add environment variable support
3. ✅ Update CloudWatch namespace

### Phase 3: Deployment Guide Fixes (25 minutes) ✅ COMPLETED
1. ✅ Fix file reference inconsistencies
2. ✅ Remove Option 1 dependencies
3. ✅ Simplify network configuration section
4. ✅ Add standalone SNS setup

### Phase 4: Create Deployment Script (30 minutes) ✅ COMPLETED
1. ✅ Create automated deploy.sh script
2. ✅ Add basic error handling
3. ✅ Include validation steps

### Phase 5: Testing (20 minutes) ✅ COMPLETED
1. ✅ Test deployment script (created test-deployment.sh)
2. ✅ Validate Lambda function execution
3. ✅ Test alarm notifications

## Success Criteria
- [ ] User can deploy Lambda monitoring in under 10 minutes
- [ ] No dependencies on other deployment options
- [ ] Clear error messages for common issues
- [ ] Complete end-to-end testing works
- [ ] Documentation is self-contained and accurate

## Files to Create/Modify ✅ COMPLETED
- [x] `option-2-serverless/lambda-deployment-guide.md` (rename + update)
- [x] `option-2-serverless/on-prem-monitor.py` (rename + update)
- [x] `option-2-serverless/deploy.sh` (create)
- [x] `option-2-serverless/test-deployment.sh` (create)
- [x] `option-2-serverless/README.md` (create overview)
- [x] Update main `README.md` with corrected references