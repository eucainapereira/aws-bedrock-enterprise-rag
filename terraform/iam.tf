# ==============================================================================
# IAM LEAST-PRIVILEGE ROLES & SECURITY POLICIES
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Bedrock Knowledge Base Service Role & Least-Privilege Policies
# ------------------------------------------------------------------------------
resource "aws_iam_role" "bedrock_kb" {
  name = "${var.project_prefix}-bedrock-kb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockTrustService"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:knowledge-base/*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "bedrock_kb" {
  name = "${var.project_prefix}-bedrock-kb-policy"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read documents strictly from the private data bucket docs/ prefix
      {
        Sid    = "S3DataSourceReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.data.arn}/docs/*"
      },
      {
        Sid    = "S3DataSourceListAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.data.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["docs/*", "docs/"]
          }
        }
      },
      # S3 Vectors vector bucket & index operations
      {
        Sid    = "S3VectorsAccess"
        Effect = "Allow"
        Action = [
          "s3vectors:PutVectors",
          "s3vectors:GetVectors",
          "s3vectors:ListVectors",
          "s3vectors:DeleteVectors",
          "s3vectors:QueryVectors",
          "s3vectors:GetIndex",
          "s3vectors:ListIndexes",
          "s3vectors:GetVectorBucket"
        ]
        Resource = [
          "arn:aws:s3vectors:${var.aws_region}:${var.aws_account_id}:bucket/${aws_s3vectors_vector_bucket.vector_bucket.vector_bucket_name}",
          "arn:aws:s3vectors:${var.aws_region}:${var.aws_account_id}:bucket/${aws_s3vectors_vector_bucket.vector_bucket.vector_bucket_name}/*"
        ]
      },
      # Titan Embeddings v2 Foundation Model invocation
      {
        Sid    = "BedrockEmbeddingModelAccess"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"
        ]
      }
    ]
  })
}

# Resource-based policy attached to the S3 Vectors Vector Bucket
resource "aws_s3vectors_vector_bucket_policy" "vector_policy" {
  vector_bucket_arn = aws_s3vectors_vector_bucket.vector_bucket.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.project_prefix}-VectorBucketPolicy"
    Statement = [
      {
        Sid    = "AllowBedrockKnowledgeBaseAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.bedrock_kb.arn
        }
        Action = [
          "s3vectors:PutVectors",
          "s3vectors:GetVectors",
          "s3vectors:ListVectors",
          "s3vectors:DeleteVectors",
          "s3vectors:QueryVectors",
          "s3vectors:GetIndex",
          "s3vectors:ListIndexes",
          "s3vectors:GetVectorBucket"
        ]
        Resource = [
          aws_s3vectors_vector_bucket.vector_bucket.arn,
          "${aws_s3vectors_vector_bucket.vector_bucket.arn}/*"
        ]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 2. AWS Lambda Execution Role & Scoped Policies
# ------------------------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name = "${var.project_prefix}-backend-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaTrustService"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.project_prefix}-backend-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs restricted specifically to function's log group
      {
        Sid    = "CloudWatchScopedLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${var.project_prefix}-backend:*"
      },
      # S3 Access restricted strictly to kpis/* folder
      {
        Sid    = "S3KpiReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.data.arn}/kpis/*"
      },
      {
        Sid    = "S3KpiListAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.data.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["kpis/*", "kpis/"]
          }
        }
      },
      # Bedrock Knowledge Base RAG retrieval operations
      {
        Sid    = "BedrockKnowledgeBaseRetrieve"
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:knowledge-base/*"
        ]
      },
      # Bedrock Foundation Models & Cross-Region Inference Profiles
      {
        Sid    = "BedrockModelInvocation"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = [
          # Amazon Nova Lite
          "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-lite-v1:0",
          "arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:inference-profile/us.amazon.nova-lite-v1:0",
          "arn:aws:bedrock:${var.aws_region}::inference-profile/us.amazon.nova-lite-v1:0",
          # Anthropic Claude 3.5 Haiku
          "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-5-haiku-20241022-v1:0",
          "arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:inference-profile/us.anthropic.claude-3-5-haiku-20241022-v1:0",
          "arn:aws:bedrock:${var.aws_region}::inference-profile/us.anthropic.claude-3-5-haiku-20241022-v1:0"
        ]
      }
    ]
  })
}

