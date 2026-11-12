terraform {
  required_version = ">= 1.10.0"

  # Remote State in existing S3 bucket with native S3 state locking
  backend "s3" {
    bucket       = "aws-bedrock-enterprise-rag-tfstate-710280692169-us-east-2-an"
    key          = "infra/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.24.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_prefix
      ManagedBy   = "Terraform"
      Environment = "Production"
      FinOps      = "Serverless-S3Vectors"
    }
  }
}

