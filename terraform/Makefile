.PHONY: help init plan apply destroy clean

# Default target
help:
	@echo "Available targets:"
	@echo "  init     - Initialize Terraform"
	@echo "  plan     - Show Terraform plan"
	@echo "  apply    - Apply Terraform configuration"
	@echo "  destroy  - Destroy all resources"
	@echo "  clean    - Clean cloned repositories and Terraform state"
	@echo "  setup    - Complete setup (init + apply)"

# Initialize Terraform
init:
	cd terraform && terraform init

# Show what will be created/changed
plan:
	cd terraform && terraform plan

# Apply the configuration
apply:
	cd terraform && terraform apply

# Destroy all resources
destroy:
	cd terraform && terraform destroy

# Clean up cloned repos and terraform state
clean:
	rm -rf terraform/assets/bedrock-access-gateway
	rm -rf terraform/assets/open-webui
	rm -rf terraform/.terraform
	rm -f terraform/.terraform.lock.hcl
	rm -f terraform/terraform.tfstate*

# Complete setup
setup: init apply
	@echo "Deployment complete! Get your URL with: cd terraform && terraform output url"

# Quick deploy (for when you've already configured terraform.tfvars)
deploy: setup