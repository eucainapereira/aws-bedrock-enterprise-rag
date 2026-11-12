# ==============================================================================
# TERRAFORM OUTPUTS
# ==============================================================================

output "api_endpoint" {
  description = "Base URL of the API Gateway HTTP API (v2)"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "website_url" {
  description = "Public URL for the S3 Static Website Hosting dashboard"
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}

output "knowledge_base_id" {
  description = "ID of the Amazon Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.kb.id
}

output "data_source_id" {
  description = "ID of the Bedrock S3 Data Source"
  value       = aws_bedrockagent_data_source.docs.data_source_id
}

output "frontend_bucket_name" {
  description = "Name of the S3 Static Website Bucket"
  value       = aws_s3_bucket.frontend.id
}

output "data_bucket_name" {
  description = "Name of the Private S3 Data Bucket"
  value       = aws_s3_bucket.data.id
}

output "vector_bucket_name" {
  description = "Name of the Amazon S3 Vectors Vector Bucket"
  value       = aws_s3vectors_vector_bucket.vector_bucket.vector_bucket_name
}

