locals {
  bag_working_dir       = "assets//bedrock-access-gateway/src"
  openwebui_working_dir = "assets/open-webui"
}

# ECR Repositories
resource "aws_ecr_repository" "bag_repository" {
  name                 = "bedrock-access-gateway"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "openwebui_repository" {
  name                 = "openwebui"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# Build and push Docker images to ECR
resource "null_resource" "build_bag_image" {
  triggers = {
    # Use static trigger to ensure consistent behavior
    repository_url = aws_ecr_repository.bag_repository.repository_url
    rebuild = "1" # Change this value to force rebuild
  }

  provisioner "local-exec" {
    working_dir = local.bag_working_dir
    command     = <<EOF
        aws ecr get-login-password --region ${var.region} --profile ${var.profile} | docker login --username AWS --password-stdin ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com
        docker build \
        -t ${aws_ecr_repository.bag_repository.repository_url}:latest \
        -f Dockerfile_ecs --platform=linux/arm64 . \
        && docker push ${aws_ecr_repository.bag_repository.repository_url}:latest
    EOF
  }

  depends_on = [aws_ecr_repository.bag_repository,
  null_resource.clone_bedrock_access_gateway]
}

resource "null_resource" "build_webui_image" {
  triggers = {
    # Use static trigger to ensure consistent behavior
    repository_url = aws_ecr_repository.openwebui_repository.repository_url
    rebuild = "1" # Change this value to force rebuild
  }

  # It may be necessary to build using NODE_OPTIONS="--max-old-space-size=4096" to make it work
  provisioner "local-exec" {
    working_dir = local.openwebui_working_dir
    command     = <<EOF
        aws ecr get-login-password --region ${var.region} --profile ${var.profile} | docker login --username AWS --password-stdin ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com
        docker build \
        -t ${aws_ecr_repository.openwebui_repository.repository_url}:latest \
        --platform=linux/arm64 . \
        && docker push ${aws_ecr_repository.openwebui_repository.repository_url}:latest
    EOF
  }

  depends_on = [aws_ecr_repository.openwebui_repository,
  null_resource.clone_open_webui]
}