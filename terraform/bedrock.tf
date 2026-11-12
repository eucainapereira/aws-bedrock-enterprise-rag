# ==============================================================================
# AMAZON BEDROCK KNOWLEDGE BASE & AMAZON S3 VECTORS (FINOPS ZERO-IDLE COST)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Amazon S3 Vectors: Vector Bucket & High-Performance Cosine Index
# ------------------------------------------------------------------------------
resource "aws_s3vectors_vector_bucket" "vector_bucket" {
  vector_bucket_name = "${var.project_prefix}-vectors-${var.aws_account_id}"
}

resource "aws_s3vectors_index" "vector_index" {
  index_name         = "${var.project_prefix}-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.vector_bucket.vector_bucket_name

  data_type       = "float32"
  dimension       = 1024
  distance_metric = "cosine"

  depends_on = [aws_s3vectors_vector_bucket.vector_bucket]
}

# ------------------------------------------------------------------------------
# 2. Amazon Bedrock Knowledge Base (Connected natively to S3 Vectors)
# ------------------------------------------------------------------------------
resource "aws_bedrockagent_knowledge_base" "kb" {
  name        = "${var.project_prefix}-kb"
  description = "Enterprise RAG Knowledge Base powered by Amazon S3 Vectors and Titan Embeddings v2"
  role_arn    = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"

      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = 1024
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.vector_index.index_arn
    }
  }

  depends_on = [
    aws_iam_role_policy.bedrock_kb,
    aws_s3vectors_vector_bucket_policy.vector_policy,
    aws_s3vectors_index.vector_index
  ]
}

# ------------------------------------------------------------------------------
# 3. Amazon Bedrock Data Source (Pointing to S3 docs/ prefix)
# ------------------------------------------------------------------------------
resource "aws_bedrockagent_data_source" "docs" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.kb.id
  name              = "${var.project_prefix}-docs-ds"
  description       = "Data Source referencing enterprise strategic documents in S3"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn         = aws_s3_bucket.data.arn
      inclusion_prefixes = ["docs/"]
    }
  }

  data_deletion_policy = "RETAIN"

  depends_on = [
    aws_bedrockagent_knowledge_base.kb,
    aws_s3_object.relatorio_estrategico
  ]
}

