# tech-blog（POSとAWSの障害対応ノート）

Hugo で作った技術ブログを、Terraform で作った S3 + CloudFront で配信しています。

- 公開先：https://d3jjg8xe1sjrq9.cloudfront.net
- 作った日：2026-11-11

## 構成

```
見る人 ──https──▶ CloudFront ──(OAC)──▶ S3（非公開）
                    │
                    └─ CloudFront Functions（/posts/abc/ → /posts/abc/index.html）

Terraform の state ──▶ 別の S3（バージョン管理・暗号化・ロック）
```

| フォルダー | 中身 |
| --- | --- |
| `bootstrap/` | state を置く S3 バケット。最初に 1 回だけ apply する（この state だけはパソコンに置く） |
| `infra/` | ブログ本体：S3・OAC・CloudFront・CloudFront Functions・バケットポリシー |
| `site/` | Hugo のサイト。テーマは使わず、レイアウトを自分で書いた |

## 4 つの目標と、したこと

| 目標 | したこと |
| --- | --- |
| ① コストパフォーマンス | サーバーを置かない静的サイト。CloudFront の Always free（月 1TB・1,000 万リクエスト）の範囲。PriceClass_200。サイト用 S3 はバージョン管理なし（元の記事は Git にある）。state の古い版は 90 日で削除。見込みは月 1〜10 円 |
| ② 障害に強い・スケールできる | CloudFront のキャッシュから配るので、アクセスが増えても S3 に負担がかからない。state はバージョン管理つきで前の版に戻せる。state のバケットは `prevent_destroy` |
| ③ 情報漏洩を起こさない | S3 は公開ブロック 4 つすべて ON、OAC で CloudFront からだけ読める（`AWS:SourceArn` で自分のディストリビューションに限定）。http は https にリダイレクト、S3 への http は拒否。セキュリティのヘッダー（HSTS など）。Terraform 用の IAM ユーザーは S3・CloudFront の権限だけで、コンソールのログインなし。バケット名・state はリポジトリに入れない |
| ④ 容量が増えても対応できる | S3 は容量の上限を気にしなくてよい。キャッシュで、アクセスが増えても S3 のリクエストと料金が増えにくい |

## 確かめたこと（2026-11-11）

- `http://` で開くと 301 で `https://` へ
- トップ・記事・`/posts/hello`（最後の / なし）が 200
- ないページは 404（Hugo の 404.html）
- S3 のオブジェクト URL を直接開くと AccessDenied
- ページを直したあと、`create-invalidation` でキャッシュを捨てて反映されることを確認

## 使い方

```powershell
# 1. state のバケット（最初の 1 回だけ）
cd bootstrap
terraform init
terraform apply

# 2. ブログ本体（backend.hcl に state のバケット名を書いておく。Git には入れない）
cd ..\infra
terraform init -backend-config="backend.hcl"
terraform apply

# 3. ページを作って置く
cd ..\site
hugo build --gc --minify
cd ..
$bucket = terraform -chdir=infra output -raw site_bucket_name
aws s3 sync site\public "s3://$bucket" --delete --profile terraform-blog

# 4. 直したときはキャッシュを捨てる
$dist = terraform -chdir=infra output -raw distribution_id
aws cloudfront create-invalidation --distribution-id $dist --paths "/*" --profile terraform-blog
```

## これからすること

- 記事を GitHub に push したら自動で公開する（GitHub Actions など）
- 独自ドメイン（Route 53・ACM）
- CloudFormation で作った [aws-portfolio](https://github.com/makoto1004/aws-portfolio) との違いを記事にする
