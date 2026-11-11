# 技術ブログの土台：最初に 1 回だけ動かす「state の置き場」
#
# state とは、Terraform が「AWS に何を作ったか」を覚えておくファイル。
# 本体（ブログの S3 + CloudFront）の state を、ここで作る S3 バケットに置く。
# このフォルダー自身の state だけは、パソコンの中（terraform.tfstate）に置く。

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-1" # 東京
  profile = "terraform-blog" # aws configure --profile terraform-blog で入れたキー

  # 作るものすべてに付く名札。料金の明細やコンソールで見分けやすくなる
  default_tags {
    tags = {
      Project   = "tech-blog"
      ManagedBy = "terraform"
    }
  }
}

# state を置く S3 バケット。
# 名前は世界で 1 つだけでないといけないので、AWS に後ろの文字を付けてもらう
resource "aws_s3_bucket" "tfstate" {
  bucket_prefix = "tfstate-tech-blog-"

  # まちがえて terraform destroy しても、このバケットは消えないようにする
  lifecycle {
    prevent_destroy = true
  }
}

# 目標③ 情報漏洩を起こさない：外から見えないようにする（4 つすべてブロック）
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 目標③：保存するときに暗号化する（追加の料金がかからない SSE-S3）
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 目標② 障害に強い：state を上書きしても、前の版に戻せるようにする
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 目標① コスト・④ 容量：古い版は 90 日たったら消す（版が増え続けないように）
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.tfstate]
}

# 目標③：暗号化されていない通信（http）での読み書きを断る
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  # 公開のブロックを先に作ってから、ポリシーを付ける
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# できたバケットの名前を表示する（本体の設定で使う）
output "tfstate_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}
