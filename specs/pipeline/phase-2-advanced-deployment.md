# Phase 2: Advanced Deployment Strategies

## Objective
Enhance the basic CI/CD pipeline with advanced deployment strategies, comprehensive testing, monitoring integration, and improved security practices.

## Prerequisites
- Phase 1 successfully implemented and stable
- Multi-environment pipeline operational
- Terraform state management working
- Basic Docker builds and deployments functional

## Phase 2 Deliverables

### 1. Enhanced Security Implementation

#### A. OIDC Authentication for AWS
Replace static AWS credentials with OpenID Connect federation.

**Required Setup:**
```hcl
# terraform/iam-github-oidc.tf
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
  
  client_id_list = [
    "sts.amazonaws.com",
  ]
  
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

resource "aws_iam_role" "github_actions" {
  for_each = toset(["dev", "staging", "prod"])
  name     = "github-actions-${each.key}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${each.key == "prod" ? "main" : each.key}",
              "repo:${var.github_org}/${var.github_repo}:pull_request"
            ]
          }
        }
      }
    ]
  })
}
```

**Workflow Updates:**
```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    role-session-name: GitHubActions-${{ github.run_id }}
    aws-region: ${{ vars.AWS_REGION }}
```

#### B. Enhanced Security Scanning

**Infrastructure Security:**
```yaml
- name: Run tfsec
  uses: aquasecurity/tfsec-action@v1.0.3
  with:
    working_directory: terraform
    format: sarif
    
- name: Run Checkov
  uses: bridgecrewio/checkov-action@master
  with:
    directory: terraform
    framework: terraform
    output_format: sarif
```

**Container Security:**
```yaml
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.ECR_REGISTRY }}/${{ matrix.service.name }}:${{ github.sha }}
    format: sarif
    output: trivy-results.sarif
    
- name: Upload Trivy scan results
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: trivy-results.sarif
```

### 2. Advanced Deployment Strategies

#### A. Blue-Green Deployment for Production

**ECS Service Configuration:**
```hcl
# terraform/ecs-blue-green.tf
resource "aws_ecs_service" "openwebui" {
  count = var.environment == "prod" ? 0 : 1
  # Standard service configuration
}

resource "aws_ecs_service" "openwebui_blue_green" {
  count = var.environment == "prod" ? 1 : 0
  
  name            = "${local.ecs.service_name_webui}-${var.deployment_slot}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.openwebui.arn
  desired_count   = var.desired_count
  
  deployment_configuration {
    deployment_circuit_breaker {
      enable   = true
      rollback = true
    }
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }
  
  load_balancer {
    target_group_arn = var.deployment_slot == "blue" ? 
      aws_lb_target_group.alb_target_group_blue.arn :
      aws_lb_target_group.alb_target_group_green.arn
    container_name   = "openwebui"
    container_port   = 8080
  }
}
```

**Deployment Workflow:**
```yaml
- name: Blue-Green Deployment
  if: github.ref == 'refs/heads/main'
  run: |
    # Determine current active slot
    CURRENT_SLOT=$(aws elbv2 describe-listeners --listener-arns $LISTENER_ARN --query 'Listeners[0].DefaultActions[0].ForwardConfig.TargetGroups[0].TargetGroupArn' --output text | grep -o 'blue\|green')
    NEW_SLOT=$([ "$CURRENT_SLOT" = "blue" ] && echo "green" || echo "blue")
    
    # Deploy to inactive slot
    terraform apply -var="deployment_slot=$NEW_SLOT" -target=aws_ecs_service.openwebui_blue_green
    
    # Wait for deployment
    aws ecs wait services-stable --cluster webui-bedrock-cluster --services openwebui-$NEW_SLOT
    
    # Run health checks
    ./scripts/health-check.sh $NEW_SLOT
    
    # Switch traffic
    aws elbv2 modify-listener --listener-arn $LISTENER_ARN --default-actions Type=forward,ForwardConfig="{TargetGroups=[{TargetGroupArn=$NEW_TARGET_GROUP_ARN,Weight=100}]}"
    
    # Clean up old slot after successful switch
    terraform apply -var="deployment_slot=none" -target=aws_ecs_service.openwebui_blue_green
```

#### B. Canary Deployment for Staging

**Traffic Splitting Configuration:**
```yaml
- name: Canary Deployment
  if: github.ref == 'refs/heads/staging'
  run: |
    # Deploy canary version
    terraform apply -var="canary_enabled=true" -var="canary_weight=10"
    
    # Monitor metrics for 10 minutes
    ./scripts/monitor-canary.sh
    
    # If successful, gradually increase traffic
    for weight in 25 50 75 100; do
      terraform apply -var="canary_weight=$weight"
      ./scripts/monitor-canary.sh
      sleep 300
    done
```

#### C. Rolling Updates for Development

Standard ECS rolling deployment with enhanced monitoring:
```yaml
- name: Rolling Update
  if: github.ref == 'refs/heads/dev'
  run: |
    terraform apply -auto-approve
    
    # Wait for deployment with timeout
    timeout 600 aws ecs wait services-stable --cluster webui-bedrock-cluster --services openwebui
    
    # Verify deployment
    ./scripts/smoke-test.sh
```

### 3. Comprehensive Testing Framework

#### A. Infrastructure Testing with Terratest

**Test Structure:**
```
terraform/
├── test/
│   ├── unit/
│   │   ├── vpc_test.go
│   │   ├── ecs_test.go
│   │   └── ecr_test.go
│   ├── integration/
│   │   ├── full_stack_test.go
│   │   └── service_connectivity_test.go
│   └── e2e/
│       └── user_journey_test.go
```

**Sample Test Implementation:**
```go
// terraform/test/unit/ecs_test.go
func TestECSCluster(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir: "../",
        Vars: map[string]interface{}{
            "account_id": "123456789012",
            "region":     "eu-west-1",
            "profile":    "test",
        },
    }
    
    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)
    
    clusterName := terraform.Output(t, terraformOptions, "cluster_name")
    assert.Equal(t, "webui-bedrock-cluster", clusterName)
}
```

**Test Workflow:**
```yaml
- name: Run Terratest
  run: |
    cd terraform/test
    go mod tidy
    go test -v -timeout 30m ./unit/...
    go test -v -timeout 60m ./integration/...
```

#### B. Application Health Checks

**Health Check Scripts:**
```bash
#!/bin/bash
# scripts/health-check.sh

ENVIRONMENT=$1
ALB_DNS=$(terraform output -raw url)

# Test OpenWebUI
curl -f "http://${ALB_DNS}/health" || exit 1

# Test Bedrock Gateway
curl -f "http://${ALB_DNS}/bedrock/health" || exit 1

# Test MCPO
curl -f "http://${ALB_DNS}/mcpo/health" || exit 1

echo "All health checks passed for $ENVIRONMENT"
```

#### C. Load Testing Integration

**k6 Load Tests:**
```javascript
// tests/load/basic-load-test.js
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 10 },
    { duration: '5m', target: 10 },
    { duration: '2m', target: 0 },
  ],
};

export default function() {
  let response = http.get(process.env.TARGET_URL);
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
}
```

### 4. Monitoring and Observability

#### A. CloudWatch Integration

**Enhanced Monitoring Configuration:**
```hcl
# terraform/monitoring.tf
resource "aws_cloudwatch_log_group" "ecs_logs" {
  for_each = toset(["openwebui", "bedrock-access-gateway", "mcpo"])
  
  name              = "/ecs/${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "aws-openwebui-${var.environment}"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", aws_ecs_service.openwebui.name],
            ["AWS/ECS", "MemoryUtilization", "ServiceName", aws_ecs_service.openwebui.name],
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "ECS Metrics"
        }
      }
    ]
  })
}
```

#### B. Application Performance Monitoring

**X-Ray Tracing:**
```hcl
resource "aws_ecs_task_definition" "openwebui" {
  # ... existing configuration
  
  container_definitions = jsonencode([
    {
      name = "openwebui"
      # ... existing config
      environment = [
        {
          name  = "_X_AMZN_TRACE_ID"
          value = "Root=1-5e1b4151-5ac6c58dc8862d71b0d8b6b0"
        }
      ]
    },
    {
      name  = "xray-daemon"
      image = "amazon/aws-xray-daemon:latest"
      portMappings = [
        {
          containerPort = 2000
          protocol      = "udp"
        }
      ]
    }
  ])
}
```

#### C. Alerting Configuration

**CloudWatch Alarms:**
```hcl
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  for_each = toset(["openwebui", "bedrock-access-gateway", "mcpo"])
  
  alarm_name          = "${each.key}-high-cpu-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS CPU utilization"
  
  dimensions = {
    ServiceName = each.key
    ClusterName = aws_ecs_cluster.ecs_cluster.name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

### 5. Cost Optimization and Management

#### A. Cost Estimation in PRs

**Infracost Integration:**
```yaml
- name: Run Infracost
  uses: infracost/infracost-action@v1
  with:
    path: terraform
    api_key: ${{ secrets.INFRACOST_API_KEY }}
    
- name: Post Infracost comment
  uses: infracost/infracost-action@v1
  with:
    path: terraform
    behavior: update
```

#### B. Resource Scheduling

**Auto-scaling Configuration:**
```hcl
resource "aws_application_autoscaling_target" "ecs_target" {
  max_capacity       = var.environment == "prod" ? 10 : 3
  min_capacity       = var.environment == "prod" ? 2 : 1
  resource_id        = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.openwebui.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_application_autoscaling_policy" "scale_up" {
  name               = "scale-up"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_application_autoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_application_autoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_application_autoscaling_target.ecs_target.service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
```

### 6. Enhanced Rollback Mechanisms

#### A. Automated Rollback on Failure

**Deployment Pipeline with Rollback:**
```yaml
- name: Deploy with Rollback
  run: |
    # Store current state
    CURRENT_TASK_DEF=$(aws ecs describe-services --cluster webui-bedrock-cluster --services openwebui --query 'services[0].taskDefinition')
    
    # Deploy new version
    terraform apply -auto-approve
    
    # Wait and test
    if ! ./scripts/health-check.sh; then
      echo "Health checks failed, rolling back..."
      aws ecs update-service --cluster webui-bedrock-cluster --service openwebui --task-definition $CURRENT_TASK_DEF
      exit 1
    fi
```

#### B. Database Migration Handling

**Migration Strategy:**
```yaml
- name: Run Database Migrations
  run: |
    # Create backup
    aws rds create-db-snapshot --db-instance-identifier $DB_IDENTIFIER --db-snapshot-identifier backup-$(date +%s)
    
    # Run migrations
    ./scripts/run-migrations.sh
    
    # Verify migrations
    ./scripts/verify-migrations.sh
```

### 7. Documentation and Reporting

#### A. Deployment Reports

**Automated Documentation:**
```yaml
- name: Generate Deployment Report
  run: |
    echo "# Deployment Report - $(date)" > deployment-report.md
    echo "## Infrastructure Changes" >> deployment-report.md
    terraform show -json > tfstate.json
    jq '.values.root_module.resources[] | select(.type == "aws_ecs_service") | {name: .values.name, desired_count: .values.desired_count}' tfstate.json >> deployment-report.md
    
- name: Upload Report
  uses: actions/upload-artifact@v3
  with:
    name: deployment-report
    path: deployment-report.md
```

### 8. Success Criteria

**Phase 2 Complete When:**
- [ ] OIDC authentication fully implemented
- [ ] Blue-green deployment working for production
- [ ] Comprehensive security scanning integrated
- [ ] Automated testing covers unit, integration, and e2e scenarios
- [ ] Monitoring and alerting operational
- [ ] Cost estimation in PRs
- [ ] Automated rollback mechanisms tested
- [ ] Load testing integrated in pipeline

**Performance Targets:**
- Blue-green deployment time: < 10 minutes
- Zero-downtime deployments: 99.9% success rate
- Security scan coverage: 100% of infrastructure and containers
- Test coverage: > 80% for critical paths

### 9. Risk Mitigation Enhancements

**New Risks Addressed:**
1. **Complex deployment failures** - Mitigated by automated rollback
2. **Performance degradation** - Mitigated by load testing and monitoring
3. **Security vulnerabilities** - Mitigated by comprehensive scanning
4. **Cost overruns** - Mitigated by cost estimation and auto-scaling

### 10. Preparation for Phase 3

Phase 2 delivers:
- Robust deployment strategies
- Comprehensive monitoring
- Strong security posture
- Automated testing framework

These enable Phase 3's advanced GitOps features including drift detection and self-healing capabilities.
