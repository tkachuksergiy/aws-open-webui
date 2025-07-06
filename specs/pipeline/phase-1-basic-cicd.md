# Phase 1: Basic CI/CD Pipeline

## Objective
Establish foundational CI/CD pipeline with essential validation, planning, and deployment capabilities for the AWS Open WebUI infrastructure.

## Current State Analysis

### Infrastructure Components
- **ECS Services**: 3 Fargate services (openwebui, bedrock-access-gateway, mcpo)
- **ECR Repositories**: 3 repositories with Docker image builds triggered by file changes
- **External Dependencies**: 
  - bedrock-access-gateway (cloned from aws-samples)
  - open-webui (cloned from open-webui/open-webui)
- **Build Process**: Local Docker builds with platform-specific targeting (linux/arm64)

### Current Deployment Method
- Manual execution via `deploy.sh` or `terraform apply`
- Local AWS profile authentication
- Direct ECR image builds and pushes
- No state management or locking

## Phase 1 Deliverables

### 1. GitHub Workflows

#### A. Pull Request Validation (`.github/workflows/terraform-plan.yml`)

**Triggers:**
- Pull requests to `main`, `staging`, `dev` branches
- Paths: `terraform/**`, `.github/workflows/**`

**Jobs:**
1. **terraform-validate**
   - Checkout code
   - Setup Terraform 1.2+
   - Configure AWS credentials (temporary approach with secrets)
   - Run `terraform fmt -check`
   - Run `terraform validate`
   - Cache Terraform plugins

2. **terraform-plan**
   - Clone external repositories (bedrock-access-gateway, open-webui)
   - Apply Dockerfile modifications for open-webui
   - Run `terraform plan -out=tfplan`
   - Upload plan artifact
   - Comment plan summary on PR

3. **docker-validate**
   - Build Docker images without pushing
   - Validate Dockerfiles in all 3 asset directories
   - Check for security vulnerabilities (basic Trivy scan)

**Success Criteria:**
- All Terraform files are valid and formatted
- Plan completes without errors
- Docker builds succeed
- No critical security vulnerabilities

#### B. Deployment Pipeline (`.github/workflows/terraform-apply.yml`)

**Triggers:**
- Push to `main`, `staging`, `dev` branches
- Manual workflow dispatch with environment parameter

**Jobs:**
1. **terraform-plan**
   - Same as PR validation plan
   - Store plan artifact for apply job

2. **manual-approval** (for main branch only)
   - Use GitHub Environments feature
   - Require manual approval from designated reviewers

3. **terraform-apply**
   - Download plan artifact
   - Run `terraform apply tfplan`
   - Update ECS services if task definitions changed

4. **docker-build-push**
   - Matrix strategy for 3 services
   - Build and push to ECR with commit SHA tags
   - Update ECS task definitions with new image URIs
   - Force new deployment for affected services

**Environment Variables per Branch:**
```yaml
dev:
  AWS_ACCOUNT_ID: ${{ secrets.AWS_ACCOUNT_ID_DEV }}
  AWS_REGION: ${{ vars.AWS_REGION_DEV }}
  TF_VAR_account_id: ${{ secrets.AWS_ACCOUNT_ID_DEV }}
  TF_VAR_region: ${{ vars.AWS_REGION_DEV }}
  TF_VAR_profile: "github-actions"

staging:
  AWS_ACCOUNT_ID: ${{ secrets.AWS_ACCOUNT_ID_STAGING }}
  AWS_REGION: ${{ vars.AWS_REGION_STAGING }}
  # ... similar pattern

production:
  AWS_ACCOUNT_ID: ${{ secrets.AWS_ACCOUNT_ID_PROD }}
  AWS_REGION: ${{ vars.AWS_REGION_PROD }}
  # ... similar pattern
```

### 2. Terraform State Management

#### Backend Configuration
Create environment-specific backend configurations:

**terraform/backends/dev.tf:**
```hcl
terraform {
  backend "s3" {
    bucket         = "aws-open-webui-terraform-state-dev"
    key            = "terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "aws-open-webui-terraform-locks-dev"
    encrypt        = true
  }
}
```

**Similar files for staging and production environments**

#### State Resources
Create S3 buckets and DynamoDB tables for state management:
```hcl
# terraform/state-resources/main.tf
resource "aws_s3_bucket" "terraform_state" {
  for_each = toset(["dev", "staging", "prod"])
  bucket   = "aws-open-webui-terraform-state-${each.key}"
}

resource "aws_dynamodb_table" "terraform_locks" {
  for_each = toset(["dev", "staging", "prod"])
  name     = "aws-open-webui-terraform-locks-${each.key}"
  # ... configuration
}
```

### 3. Environment-Specific Configurations

#### Variable Files
**terraform/environments/dev.tfvars:**
```hcl
account_id = "123456789012"  # Dev account
region     = "eu-west-1"
profile    = "github-actions"

# Environment-specific overrides
cluster_name_suffix = "-dev"
instance_count      = 1
```

**Similar files for staging and production**

#### Modified Variables
Extend `terraform/variables.tf`:
```hcl
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name_suffix" {
  description = "Suffix for cluster name"
  type        = string
  default     = ""
}
```

### 4. External Repository Management

#### Enhanced Git Repository Handling
Modify `terraform/git_repositories.tf`:
```hcl
resource "null_resource" "clone_bedrock_access_gateway" {
  triggers = {
    # Use specific commit SHAs instead of timestamp for reproducibility
    bedrock_gateway_ref = var.bedrock_gateway_ref
  }

  provisioner "local-exec" {
    command = <<EOF
      rm -rf assets/bedrock-access-gateway
      git clone https://github.com/aws-samples/bedrock-access-gateway assets/bedrock-access-gateway
      cd assets/bedrock-access-gateway && git checkout ${var.bedrock_gateway_ref}
    EOF
  }
}
```

Add variables for repository references:
```hcl
variable "bedrock_gateway_ref" {
  description = "Git reference for bedrock-access-gateway"
  type        = string
  default     = "main"
}

variable "open_webui_ref" {
  description = "Git reference for open-webui"
  type        = string
  default     = "main"
}
```

### 5. Docker Build Optimization

#### Multi-stage Matrix Build
```yaml
strategy:
  matrix:
    service:
      - name: bedrock-access-gateway
        dockerfile: Dockerfile_ecs
        context: terraform/assets/bedrock-access-gateway/src
        platform: linux/arm64
      - name: openwebui
        dockerfile: Dockerfile
        context: terraform/assets/open-webui
        platform: linux/amd64
      - name: mcpo
        dockerfile: Dockerfile
        context: terraform/assets/mcpo
        platform: linux/amd64
```

#### Change Detection
Only build and deploy services that have changed:
```yaml
- name: Detect changes
  uses: dorny/paths-filter@v2
  id: changes
  with:
    filters: |
      bedrock-gateway:
        - 'terraform/assets/bedrock-access-gateway/**'
      open-webui:
        - 'terraform/assets/open-webui/**'
      mcpo:
        - 'terraform/assets/mcpo/**'
      terraform:
        - 'terraform/*.tf'
```

### 6. Required GitHub Secrets and Variables

#### Secrets (Environment-specific)
- `AWS_ACCOUNT_ID_DEV/STAGING/PROD`
- `AWS_ACCESS_KEY_ID_DEV/STAGING/PROD` (temporary, to be replaced with OIDC in Phase 2)
- `AWS_SECRET_ACCESS_KEY_DEV/STAGING/PROD` (temporary)

#### Variables (Environment-specific)
- `AWS_REGION_DEV/STAGING/PROD`
- `BEDROCK_GATEWAY_REF_DEV/STAGING/PROD`
- `OPEN_WEBUI_REF_DEV/STAGING/PROD`

### 7. Documentation Updates

#### README.md Updates
Add sections for:
- CI/CD pipeline overview
- Environment setup instructions
- Manual deployment vs automated deployment
- Troubleshooting common pipeline issues

#### Deployment Guide
Create `docs/deployment.md` with:
- Prerequisites for GitHub Actions setup
- Environment configuration steps
- Manual approval process
- Rollback procedures

### 8. Success Criteria

**Phase 1 Complete When:**
- [ ] PR validation prevents broken Terraform from merging
- [ ] Successful deployment to dev environment on push to dev branch
- [ ] Manual approval gate works for production deployments
- [ ] Docker images are automatically built and deployed
- [ ] Terraform state is managed remotely with locking
- [ ] Each environment has isolated infrastructure
- [ ] Documentation is complete and tested

**Key Metrics:**
- Deployment time: < 15 minutes for full stack
- Success rate: > 95% for valid changes
- Mean Time to Recovery: < 5 minutes for rollbacks

### 9. Risk Mitigation

**Identified Risks:**
1. **External repository dependencies** - Mitigated by pinning to specific refs
2. **Docker build failures** - Mitigated by validation in PR pipeline
3. **Terraform state corruption** - Mitigated by S3 versioning and DynamoDB locking
4. **AWS credential exposure** - Temporarily using secrets, OIDC in Phase 2

**Rollback Strategy:**
- Keep previous Docker image tags in ECR
- Terraform state file backups in S3
- Manual override capabilities for emergency deployments

### 10. Next Phase Prerequisites

Phase 1 must deliver:
- Working multi-environment pipeline
- Reliable state management
- Basic security scanning
- Comprehensive documentation

These form the foundation for Phase 2's advanced deployment strategies and monitoring.
