# 技術ブログの本体：S3（ページの置き場）＋ CloudFront（配る仕組み）＋ OAC
#
# state は bootstrap で作った S3 バケットに置く。
# バケット名は backend.hcl に書いてある（GitHub には載せない）。
#   terraform init -backend-config=backend.hcl

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key          = "tech-blog/infra.tfstate"
    region       = "ap-northeast-1"
    profile      = "terraform-blog"
    encrypt      = true
    use_lockfile = true # 同時に 2 人が apply しないためのロック（S3 だけでできる）
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "terraform-blog"

  default_tags {
    tags = {
      Project   = "tech-blog"
      ManagedBy = "terraform"
    }
  }
}

# ---------------------------------------------------------------
# S3：Hugo が作ったページを置くバケット
# ---------------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket_prefix = "tech-blog-site-"
}

# 目標③ 情報漏洩を起こさない：S3 は非公開のまま。見せるのは CloudFront だけ
resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# バージョン管理は付けない：元の Markdown は GitHub にあり、
# ページは Hugo で何度でも作り直せるため（目標① コスト）

# ---------------------------------------------------------------
# CloudFront
# ---------------------------------------------------------------

# OAC：CloudFront だけが S3 を読めるようにする「通行証」
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "tech-blog-oac"
  description                       = "CloudFront から技術ブログの S3 を読むため"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Functions：/posts/abc/ のような URL に index.html を付けて S3 に聞く
# （Hugo は記事ごとにフォルダーと index.html を作るため）
resource "aws_cloudfront_function" "add_index" {
  name    = "tech-blog-add-index"
  runtime = "cloudfront-js-2.0"
  comment = "末尾が / か、拡張子がない URL に index.html を付ける"
  publish = true
  code    = file("${path.module}/add-index.js")
}

# AWS が用意している設定（ID は AWS 共通で固定）
locals {
  cache_policy_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6" # 長くキャッシュする
  response_headers_security      = "67f7725c-6f97-4210-82d7-5512b31e9d03" # セキュリティのヘッダーを付ける
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "tech-blog"
  default_root_object = "index.html"
  is_ipv6_enabled     = true
  http_version        = "http2and3"

  # 目標① コスト：北米・ヨーロッパ・日本を含むアジアの拠点だけを使う
  price_class = "PriceClass_200"

  origin {
    origin_id                = "s3-site"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-site"
    viewer_protocol_policy = "redirect-to-https" # http で来たら https に移す
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # 目標② ④：キャッシュから配るので、アクセスが増えても S3 に負担がかからない
    cache_policy_id = local.cache_policy_caching_optimized

    # 目標③：ブラウザーに「https だけで来て」「ほかのサイトの中に表示させない」などを伝える
    response_headers_policy_id = local.response_headers_security

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.add_index.arn
    }
  }

  # ないページは、S3 が 403 を返す（一覧を見る権限を渡していないため）。
  # 見る人には Hugo の 404.html を、404 として見せる
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # URL は 〜.cloudfront.net のまま（独自ドメインは 2 月以降）
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ---------------------------------------------------------------
# バケットポリシー：この CloudFront からの読み取りだけを許す
# ---------------------------------------------------------------

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontRead"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ---------------------------------------------------------------
# 表示するもの
# ---------------------------------------------------------------

output "site_url" {
  value = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "site_bucket_name" {
  value = aws_s3_bucket.site.bucket
}

output "distribution_id" {
  value = aws_cloudfront_distribution.site.id
}
