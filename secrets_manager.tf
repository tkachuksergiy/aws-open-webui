# API Key secrets for Bedrock Access Gateway
resource "random_password" "bag_api_key" {
  length  = 10
  special = true
}

resource "aws_secretsmanager_secret" "bag_api_key_secret" {
  name_prefix = "bag-api-key-"
}

resource "aws_secretsmanager_secret_version" "bag_api_key_secret_version" {
  secret_id     = aws_secretsmanager_secret.bag_api_key_secret.id
  secret_string = random_password.bag_api_key.result
}

# Other secrets