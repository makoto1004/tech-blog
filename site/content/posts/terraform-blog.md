---
title: CloudFormation で作った構成を Terraform で作り直して、技術ブログの土台にする
date: 2026-11-11
description: CloudFormation で作った S3 + CloudFront + OAC の構成を Terraform で作り直し、Hugo の技術ブログの土台にしました。state の置き場、確かめたこと、2 つの違いをまとめます。
---

2026年11月10〜11日に、前回作った構成を Terraform で作り直し、自分の技術ブログを公開しました。
前回は CloudFormation とスクリプトで作って消しましたが、今回は構成を置いたままにします。

IT 派遣でヘルプデスクや POS レジの仕事をしています。
AWS SAA、AWS Cloud Practitioner、LPIC-1を取得し、社内 SE かクラウド運用への転職に向けて練習しています。

## 作ったもの

前回は、CloudFormation の `template.yaml` 1つで S3、OAC、CloudFront、バケットポリシー、Budgets を作りました。
S3 は公開ブロックを4つ有効にし、SSE-S3 で暗号化しました。
CloudFront は `PriceClass_200`、HTTP から HTTPS へのリダイレクト、`CachingOptimized`、`SecurityHeadersPolicy` を設定しました。
`deploy.ps1` で作り、`delete.ps1` で削除しました。
コードは [aws-portfolio](https://github.com/makoto1004/aws-portfolio) にあります。

今回は Terraform v1.17.0 と AWS プロバイダー v6.72.0 で、ブログを配信する構成を作りました。
Terraform は、設定ファイルに書いた内容をもとにインフラを作成・変更するツールです。
コードは [tech-blog](https://github.com/makoto1004/tech-blog) に置きました。
公開前に、キー、アカウント ID、バケット名、メールアドレスが含まれていないことを確認しました。

構成は `bootstrap` と `infra` の2つに分けました。
`bootstrap` は Terraform の記録を置く S3 バケットを作り、最初に1回だけ `apply` します。
`infra` はブログ本体の S3、OAC、CloudFront、CloudFront Functions、バケットポリシーを作ります。

## state の置き場を先に作る

state は、Terraform が「AWS に何を作ったか」を覚えておくファイルです。
`bootstrap` の state だけはパソコンに置き、ブログ本体の state は `bootstrap` で作った S3 バケットに置きました。

state 用バケットには、公開ブロック4つ、SSE-S3 による暗号化、バージョン管理、古い版を90日で削除する設定を入れました。
HTTP での読み書きを拒否するバケットポリシーと `prevent_destroy` も設定しました。
`prevent_destroy` は、誤って `destroy` しても対象リソースを削除させない設定です。

バケット名は `bucket_prefix` で AWS に自動で付けてもらいました。
state のバケット名は `backend.hcl` に書き、`.gitignore` で GitHub に載らないようにしました。
`infra` のバックエンドでは `use_lockfile = true` を指定し、S3 だけで state をロックするようにしました。

## Terraform 用の IAM ユーザー

Terraform 用に `terraform-deployers` グループと `terraform-blog` ユーザーを作りました。
グループには `AmazonS3FullAccess` と `CloudFrontFullAccess` だけを付け、`AdministratorAccess` は付けませんでした。

アクセスキーは `aws configure --profile terraform-blog` で設定しました。
前からある `default` プロファイルとは分け、`aws sts get-caller-identity` で使用するユーザーを確認しました。

## plan と apply

`bootstrap` は `terraform init` のあと `terraform plan` を実行しました。
`Plan: 6 to add, 0 to change, 0 to destroy` を確認してから `terraform apply` を実行し、`Apply complete! Resources: 6 added` になりました。

`infra` は `terraform init -backend-config="backend.hcl"` のあと `terraform plan` を実行し、7つ追加されることを確認しました。
続けて `terraform apply` を実行し、7つ追加しました。
CloudFront の作成には数分かかりました。

## Hugo でページを作って置く

ブログは Hugo v0.169.0 extended で作りました。
Hugo は、記事などから静的な HTML ページを作るツールです。
テーマは使わず、自分でレイアウトを書きました。
外部サイトからフォントや JavaScript を読み込まない構成にし、最初の記事「このブログについて」を作りました。

作業フォルダーは OneDrive の外に置きました。
`.terraform` に数百 MB の部品がダウンロードされるためです。
ページは `hugo build --gc --minify` で作り、`aws s3 sync site\public "s3://（バケット）" --delete --profile terraform-blog` で S3 に置きました。

Hugo は記事ごとにフォルダーと `index.html` を作ります。
CloudFront Functions は、`/posts/abc/` や `/posts/abc` を `/posts/abc/index.html` につなぐようにしました。
CloudFront Functions は、CloudFront の配信時にリクエストを書き換える仕組みです。

S3 は一覧を取得する権限を渡していないため、ないページへのアクセスには403を返します。
CloudFront で403を404に変え、Hugo の `404.html` を表示するようにしました。

## 確かめたこと

2026年11月11日に、HTTP の URL が301で HTTPS にリダイレクトされることを確認しました。
HSTS、`X-Frame-Options`、`X-Content-Type-Options: nosniff` の各ヘッダーが付くことも確認しました。

トップページ、`/posts/hello/`、末尾の `/` がない `/posts/hello`、`/posts/` が200になることを確認しました。
ないページは404になり、「ページが見つかりません」の画面になることも確認しました。
S3 のオブジェクト URL を直接開くと `AccessDenied` になることを確認しました。

最初は一覧と404画面のタイトルが `Posts` と `404 Page not found` になっていました。
タイトルを直してから再度同期し、`aws cloudfront create-invalidation --paths "/*"` を実行しました。
修正が配信に反映されたことを確認しました。

## つまずいたところ

IAM ユーザーを作るとき、「コンソールへのアクセス」が有効になり、パスワードが作られました。
「セキュリティ認証情報」タブで「コンソールアクセスを無効にする」に戻しました。
このユーザーは Terraform がアクセスキーで使うだけです。

Terraform を2つ同時に動かしたとき、`another process has locked a portion of the file` と表示されて止まりました。
これは state のロックで、同時に state を書き換えないための仕組みです。
1つの処理が終わってからやり直しました。

ページを置く前は、ないページが404ではなく403になりました。
`404.html` がまだなかったためです。
ページを置いたあと、404になることを確認しました。

## CloudFormation との違い

| 比較したこと | CloudFormation | Terraform |
|---|---|---|
| 作ったものの記録 | AWS がスタックとして持つ | state ファイルの置き場所、ロック、保護を自分で用意する |
| 変更前の確認 | 変更セットの仕組みがある。今回は使っていない | `plan` で追加・変更・削除の数を確認する |
| 書き方 | YAML で書き、`!Sub` や `!GetAtt` で値を参照する | HCL で書き、`aws_s3_bucket.site.arn` のように参照する。ポリシーには `jsonencode` を使う |
| S3 の設定 | バケット1つの中に設定を書く | 公開ブロック、暗号化、バージョン管理などが別のリソースに分かれる |
| 削除 | スタックを消すとまとめて削除される | `destroy` で削除する。`prevent_destroy` で対象を守れる |

今回使ってみて、Terraform では変更前に `plan` で差分を確認できることと、state の置き場を自分で用意することが印象に残りました。
前回は作って消しましたが、今回はブログの土台として置いたままにします。

## 4つの目標でしたこと

| 目標 | 今回したこと |
|---|---|
| ① コストパフォーマンス | サーバーを置かない静的サイトにし、CloudFront は Always free（ずっと無料の枠。毎月 1TB のデータ転送と 1,000 万リクエストまで）の範囲と `PriceClass_200` を使いました。サイト用 S3 は、元の記事を Git に置いているためバージョン管理を付けませんでした。state の古い版は90日で削除します。作成前に公式の料金ページで計算しました。 |
| ② 障害に強く、スケールできる | CloudFront のキャッシュから配信し、アクセスが増えても S3 に負担がかかりにくい構成にしました。state はバージョン管理で前の版に戻せるようにし、`prevent_destroy` も設定しました。 |
| ③ 情報漏洩を起こさない | S3 を非公開にし、OAC で自分の配信からだけ読めるようにしました。HTTPS とセキュリティヘッダーを設定しました。IAM は S3 と CloudFront の権限だけにし、コンソールにはログインできない設定にしました。バケット名と state は GitHub に載せないようにしました。 |
| ④ 容量が増えても対応できる | S3 は容量の上限を気にせず使える構成にしました。CloudFront のキャッシュで、アクセスが増えても S3 へのリクエストが増えにくくなるようにしました。 |

## 次回やること

次回は、使っていないのに料金がかかるリソースを毎晩調べて、メールで知らせる「消し忘れチェッカー」を Terraform で作ります。

## 参考にした情報

- Terraform ドキュメント「Backend Type: s3」
- AWS CloudFront 開発者ガイド「Restrict access to an Amazon S3 origin」
- Hugo ドキュメント「Introduction to templating」
