# AWS Open WebUI - CI/CD Pipeline Specifications

This directory contains detailed specifications for implementing a comprehensive GitHub Actions CI/CD pipeline for the AWS Open WebUI Terraform infrastructure.

## Overview

The pipeline is designed to automate the deployment and management of a multi-service ECS application consisting of:
- **OpenWebUI** - Web interface for AI interactions
- **Bedrock Access Gateway** - AWS Bedrock proxy service
- **MCPO** - Model Context Protocol service

## Current Infrastructure

### Terraform Components
- **ECS Cluster**: `webui-bedrock-cluster` with 3 Fargate services
- **ECR Repositories**: 3 repositories for containerized services
- **Application Load Balancer**: Public-facing ALB with target groups
- **VPC**: Custom VPC with public/private subnets and security groups
- **External Dependencies**: Git repositories cloned during deployment

### Key Infrastructure Files
- `ecs.tf` - ECS cluster, services, ALB configuration (530 lines)
- `ecr.tf` - ECR repositories and Docker image builds (86 lines)
- `vpc.tf` - Network infrastructure
- `git_repositories.tf` - External repo management (41 lines)
- `variables.tf` - Input variables (account_id, region, profile)

## Implementation Phases

### [Phase 1: Basic CI/CD](./phase-1-basic-cicd.md)
Foundation pipeline with essential validation, planning, and deployment workflows.

### [Phase 2: Advanced Deployment](./phase-2-advanced-deployment.md)
Enhanced deployment strategies, comprehensive testing, and monitoring integration.

### [Phase 3: Full GitOps](./phase-3-full-gitops.md)
Complete GitOps implementation with drift detection, self-healing, and advanced security.

## Environment Strategy

- **Development**: `dev` branch → development environment
- **Staging**: `staging` branch → staging environment  
- **Production**: `main` branch → production environment

Each environment will have:
- Separate Terraform state files
- Environment-specific variables
- Appropriate approval gates
- Isolated AWS resources

## Security Considerations

- OIDC authentication for AWS (no long-lived credentials)
- Terraform state encryption and locking
- Container vulnerability scanning
- Infrastructure security scanning with tfsec/checkov
- Secrets management through GitHub secrets
