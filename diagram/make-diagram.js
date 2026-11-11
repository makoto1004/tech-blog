// 技術ブログの土台の AWS 構成図を draw.io 形式（.drawio）で作る。アイコンは draw.io の AWS 公式アイコン（aws4）
// 使い方：node make-diagram.js → architecture.drawio
//         PNG は C:\Users\makoto0492\OneDrive\ドキュメント\store-it-diagram\render.js で作る
const fs = require('fs')
const path = require('path')

const FONT = 'fontFamily=Yu Gothic;'
const cells = []
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/\n/g, '&#xa;')
const box = (id, value, x, y, w, h, style) =>
  cells.push(`<mxCell id="${id}" value="${esc(value)}" style="${style}" vertex="1" parent="1"><mxGeometry x="${x}" y="${y}" width="${w}" height="${h}" as="geometry"/></mxCell>`)
const line = (id, src, dst, style, label = '', pts = []) => {
  const points = pts.length ? `<Array as="points">${pts.map(([x, y]) => `<mxPoint x="${x}" y="${y}"/>`).join('')}</Array>` : ''
  cells.push(`<mxCell id="${id}" value="${esc(label)}" style="${style}" edge="1" parent="1" source="${src}" target="${dst}"><mxGeometry relative="1" as="geometry">${points}</mxGeometry></mxCell>`)
}

const icon = (res, color) => `sketch=0;outlineConnect=0;fontColor=#232F3E;strokeColor=#ffffff;fillColor=${color};dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=0;${FONT}fontSize=14;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.${res};`
const person = (shape) => `sketch=0;outlineConnect=0;fontColor=#232F3E;fillColor=#232F3E;strokeColor=none;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=0;${FONT}fontSize=14;aspect=fixed;shape=mxgraph.aws4.${shape};`
const group = (gr, color) => `points=[];outlineConnect=0;html=0;whiteSpace=wrap;${FONT}fontSize=15;fontStyle=1;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.${gr};strokeColor=${color};fillColor=none;verticalAlign=top;align=left;spacingLeft=34;fontColor=${color};dashed=0;`
const text = (size, color, extra = '') => `text;html=0;whiteSpace=wrap;${FONT}fontSize=${size};fontColor=${color};align=left;verticalAlign=top;strokeColor=none;fillColor=none;${extra}`
const arrow = (color, dashed = false) => `edgeStyle=orthogonalEdgeStyle;rounded=0;html=0;${FONT}fontSize=13;labelBackgroundColor=#ffffff;endArrow=block;endFill=1;strokeWidth=2;strokeColor=${color};` + (dashed ? 'dashed=1;' : '')
const RIGHT = 'labelPosition=right;verticalLabelPosition=middle;align=left;verticalAlign=middle;spacingLeft=6;'
const ABOVE = 'verticalLabelPosition=top;verticalAlign=bottom;'
const side = (ex, ey, nx, ny) => `exitX=${ex};exitY=${ey};entryX=${nx};entryY=${ny};`

box('title', '技術ブログの土台：Hugo のページを S3 + CloudFront で配信する構成（Terraform）', 40, 20, 1180, 36, text(24, '#232F3E', 'fontStyle=1;'))
box('sub', 'S3 は非公開。CloudFront の OAC からだけ読める。AWS の物はすべて Terraform で作り、state は別の S3 に置く。コードは GitHub（makoto1004/tech-blog）。', 40, 58, 1180, 24, text(14, '#5f6b7a'))

// 見る人
box('users', '見る人\n（スマホ・PC）', 70, 220, 64, 64, person('users'))

// AWS
box('cloud', 'AWS Cloud', 250, 110, 960, 530, group('group_aws_cloud_alt', '#232F3E'))
box('cf', 'CloudFront\nHTTPS へ転送・SecurityHeadersPolicy\nCloudFront Functions（/ → index.html）\nない所は 404 のページ', 400, 220, 64, 64, icon('cloudfront', '#8C4FFF') + ABOVE)
box('iam', 'IAM ユーザー\nterraform-blog\nS3・CloudFront の権限だけ\nコンソールのログインなし', 400, 430, 64, 64, icon('identity_and_access_management', '#DD344C'))

box('region', '東京リージョン（ap-northeast-1）', 615, 150, 565, 460, group('group_region', '#00A4A6') + 'dashed=1;')
box('site', 'S3（ブログのページ）\nパブリックアクセスはすべてブロック\n暗号化（SSE-S3）\nこの配信からの GetObject だけ許可', 700, 220, 64, 64, icon('s3', '#7AA116') + RIGHT)
box('state', 'S3（Terraform の state）\nバージョン管理・暗号化\nuse_lockfile でロック\nhttp は拒否・prevent_destroy', 700, 430, 64, 64, icon('s3', '#7AA116') + RIGHT)

line('e1', 'users', 'cf', arrow('#232F3E') + side(1, 0.5, 0, 0.5), 'HTTPS')
line('e2', 'cf', 'site', arrow('#8C4FFF') + side(1, 0.5, 0, 0.5), 'OAC（署名つき）\n読み取りだけ')

// 自分の PC
box('pc', '自分の PC\nTerraform・Hugo\n（キーは terraform-blog）', 70, 560, 64, 64, person('client'))
line('e3', 'pc', 'state', arrow('#E7157B', true) + side(1, 0.5, 0.5, 1), '① terraform plan → apply\n（AWS の物を作る・state を読み書き）', [[732, 592]])
line('e4', 'pc', 'site', arrow('#7AA116', true) + side(0.75, 0, 0.5, 1), '② hugo build → aws s3 sync（ページを置く）', [[118, 385], [732, 385]])
line('e5', 'pc', 'cf', arrow('#8C4FFF', true) + side(0.25, 0, 0.5, 1), '③ キャッシュの無効化', [[86, 345], [432, 345]])

box('note', '4 つの目標でしたこと\n① コスト：サーバーなしの静的サイト。CloudFront の Always free の範囲・PriceClass_200。state の古い版は 90 日で削除\n② 障害に強い：CloudFront のキャッシュから配る。state はバージョン管理で前の版に戻せる\n③ 漏洩させない：S3 は非公開・OAC・HTTPS だけ。IAM は必要な権限だけ。バケット名と state は GitHub に載せない\n④ 容量：S3 は上限を気にしなくてよい。キャッシュでアクセスが増えても S3 の負担が増えにくい', 250, 680, 960, 130, text(15, '#232F3E', 'spacing=4;'))

const xml = `<mxfile host="make-diagram.js" type="device"><diagram id="aws" name="構成図"><mxGraphModel dx="1260" dy="840" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1260" pageHeight="840" background="#ffffff" math="0" shadow="0"><root><mxCell id="0"/><mxCell id="1" parent="0"/>${cells.join('')}</root></mxGraphModel></diagram></mxfile>`
const out = path.join(__dirname, 'architecture.drawio')
fs.writeFileSync(out, xml)
console.log(out, cells.length, 'cells')
