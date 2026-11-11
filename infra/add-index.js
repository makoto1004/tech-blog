// CloudFront Functions（見る人からのリクエストを受けたときに動く小さなプログラム）
// /posts/abc/ → /posts/abc/index.html
// /posts/abc  → /posts/abc/index.html（拡張子がないとき）
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri.endsWith('/')) {
    request.uri = uri + 'index.html';
  } else if (!uri.split('/').pop().includes('.')) {
    request.uri = uri + '/index.html';
  }

  return request;
}
