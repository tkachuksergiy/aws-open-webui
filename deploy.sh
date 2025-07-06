#!/bin/bash

# Clone Bedrock Access Gateway repository
if [ ! -d "terraform/assets/bedrock-access-gateway" ]; then
  git clone https://github.com/aws-samples/bedrock-access-gateway terraform/assets/bedrock-access-gateway
fi

# Clone Open WebUI repository
if [ ! -d "terraform/assets/open-webui" ]; then
  git clone https://github.com/open-webui/open-webui terraform/assets/open-webui
  sed -i '' 's|RUN npm run build|RUN NODE_OPTIONS="--max-old-space-size=4096" npm run build|' terraform/assets/open-webui/Dockerfile
fi

# Init and apply Terraform configuration
cd terraform && terraform init && terraform apply