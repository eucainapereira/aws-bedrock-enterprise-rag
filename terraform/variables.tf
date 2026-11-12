variable "aws_region" {
  type        = string
  description = "Target AWS Region"
  default     = "us-east-2"
}

variable "aws_account_id" {
  type        = string
  description = "Target AWS Account ID"
  default     = "710280692169"
}

variable "project_prefix" {
  type        = string
  description = "Standard naming prefix for all provisioned enterprise resources"
  default     = "aws-bedrock-enterprise-rag"
}

variable "model_id" {
  type        = string
  description = "Amazon Bedrock model ID or inference profile for RAG generation"
  default     = "us.amazon.nova-lite-v1:0"
}

variable "embedding_model_id" {
  type        = string
  description = "Amazon Bedrock Foundation Model ID for embedding generation"
  default     = "amazon.titan-embed-text-v2:0"
}

