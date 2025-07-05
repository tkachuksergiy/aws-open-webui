# Clone external repositories using Terraform
resource "null_resource" "clone_bedrock_access_gateway" {
  triggers = {
    # Use static trigger to avoid plan inconsistency
    run_once = "1"
  }

  provisioner "local-exec" {
    command = <<EOF
      if [ ! -d "assets/bedrock-access-gateway" ]; then
        git clone https://github.com/aws-samples/bedrock-access-gateway assets/bedrock-access-gateway
      else
        echo "Bedrock Access Gateway already exists, skipping clone"
      fi
    EOF
  }
}

resource "null_resource" "clone_open_webui" {
  triggers = {
    # Use static trigger to avoid plan inconsistency  
    run_once = "1"
  }

  provisioner "local-exec" {
    command = <<EOF
      if [ ! -d "assets/open-webui" ]; then
        git clone https://github.com/open-webui/open-webui assets/open-webui
        # Modify Dockerfile for memory optimization (macOS sed syntax)
        sed -i '' 'RUN NODE_OPTIONS="--max-old-space-size=4096" npm run build' assets/open-webui/Dockerfile
      else
        echo "Open WebUI already exists, skipping clone"
      fi
    EOF
  }
}

# Create assets directory
resource "null_resource" "create_assets_dir" {
  provisioner "local-exec" {
    command = "mkdir -p assets"
  }
}