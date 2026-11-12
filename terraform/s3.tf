# ==============================================================================
# S3 DATA STORAGE & STATIC FRONTEND HOSTING
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Private Enterprise Data Bucket
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "data" {
  bucket        = "${var.project_prefix}-data-${var.aws_account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Strict S3 Block Public Access (Zero Public Exposure)
resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# Upload Enterprise Datasets & Strategic Reports to S3
# Note: These objects are deployed during terraform apply so that they are guaranteed
# to exist prior to the Bedrock ingestion job trigger in the CI/CD pipeline.
# ------------------------------------------------------------------------------
resource "aws_s3_object" "faturamento_kpis" {
  bucket       = aws_s3_bucket.data.id
  key          = "kpis/faturamento_2026.csv"
  source       = "${path.module}/../data/kpis/faturamento_2026.csv"
  etag         = filemd5("${path.module}/../data/kpis/faturamento_2026.csv")
  content_type = "text/csv"

  depends_on = [
    aws_s3_bucket_public_access_block.data,
    aws_s3_bucket_server_side_encryption_configuration.data
  ]
}

resource "aws_s3_object" "relatorio_estrategico" {
  bucket       = aws_s3_bucket.data.id
  key          = "docs/relatorio_estrategico_2026.txt"
  source       = "${path.module}/../data/docs/relatorio_estrategico_2026.txt"
  etag         = filemd5("${path.module}/../data/docs/relatorio_estrategico_2026.txt")
  content_type = "text/plain; charset=utf-8"

  depends_on = [
    aws_s3_bucket_public_access_block.data,
    aws_s3_bucket_server_side_encryption_configuration.data
  ]
}

# ------------------------------------------------------------------------------
# 2. Static Website Hosting S3 Bucket (Dark Mode Dashboard)
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.project_prefix}-frontend-${var.aws_account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# Allow public read specifically for static website hosting
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Public Read Bucket Policy for Website Content Only
resource "aws_s3_bucket_policy" "frontend_public_read" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

