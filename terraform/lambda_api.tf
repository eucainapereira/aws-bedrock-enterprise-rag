# ==============================================================================
# AWS LAMBDA BACKEND & API GATEWAY HTTP API (V2)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Package Python Lambda Source Code
# ------------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../src/lambda/handler.py"
  output_path = "${path.module}/lambda_payload.zip"
}

# ------------------------------------------------------------------------------
# 2. CloudWatch Log Group for Lambda
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_prefix}-backend"
  retention_in_days = 7
}

# ------------------------------------------------------------------------------
# 3. AWS Lambda Function
# ------------------------------------------------------------------------------
resource "aws_lambda_function" "backend" {
  function_name    = "${var.project_prefix}-backend"
  description      = "Backend Lambda for RAG chat and KPI analytics aggregation"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      KNOWLEDGE_BASE_ID   = aws_bedrockagent_knowledge_base.kb.id
      DATA_BUCKET_NAME    = aws_s3_bucket.data.id
      MODEL_ID            = var.model_id
      AWS_ACCOUNT_ID      = var.aws_account_id
      CORS_ALLOWED_ORIGIN = "*"
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# ------------------------------------------------------------------------------
# 4. API Gateway HTTP API (v2) with CORS Enabled
# ------------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_prefix}-api"
  protocol_type = "HTTP"
  description   = "Serverless HTTP API for Bedrock RAG and Enterprise BI KPIs"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization", "X-Requested-With"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.backend.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Route GET /kpis
resource "aws_apigatewayv2_route" "get_kpis" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /kpis"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Route POST /chat
resource "aws_apigatewayv2_route" "post_chat" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# ------------------------------------------------------------------------------
# 5. Lambda Permission for API Gateway Invocations
# ------------------------------------------------------------------------------
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

