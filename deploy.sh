#!/bin/bash

cd terraform 

# Clone Bedrock Access Gateway repository
git clone https://github.com/aws-samples/bedrock-access-gateway

# Clone Open WebUI repository
git clone https://github.com/open-webui/open-webui

# Init and apply Terraform configuration
terraform init && terraform apply