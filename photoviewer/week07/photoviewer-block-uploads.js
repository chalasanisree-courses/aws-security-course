// ============================================================
// photoviewer-block-uploads — CloudFront Viewer Request function
//
// Week 7: Blocks all direct CloudFront requests to /uploads/*
// Uploaded photos are served via S3 presigned GET URLs only,
// not through CloudFront.
//
// This function is attached to a separate /uploads/* behavior —
// the existing allowlist function on the default behavior is
// unchanged from Week 5.
// ============================================================

function handler(event) {
    return {
        statusCode: 403,
        statusDescription: 'Forbidden'
    };
}
