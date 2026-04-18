// ============================================================
// photoviewer-allowlist — CloudFront Viewer Request function
//
// Allowlist: only these file types are served.
// Everything else — .txt, .env, .zip, unknown extensions — 
// returns 403 at the edge before reaching S3.
//
// Stage 2: html, js, css, jpg, json
// (json added to support /photos.json static photo list)
// ============================================================

function handler(event) {
    var uri = event.request.uri;

    // Allow the root path — CloudFront serves index.html
    // via the default root object setting
    if (uri === '/') {
        return event.request;
    }

    // Allowlist: permitted file extensions regardless of folder depth
    // /photos/photo1.jpg  ✓
    // /photos.json        ✓
    // /confidential.txt   ✗ → 403
    var allowed = /\.(html|js|css|jpg|json)$/i;

    if (allowed.test(uri)) {
        return event.request;
    }

    return {
        statusCode: 403,
        statusDescription: 'Forbidden'
    };
}
