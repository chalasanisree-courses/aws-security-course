#!/usr/bin/env bash
# week6-preflight.sh
# Verifies your Week 5 environment is intact before starting Week 6.
# Run from CloudShell:
#   bash aws-security-course/photoviewer/week06/week6-preflight.sh

set -euo pipefail

REGION="us-east-1"
TABLE="photoviewer-photos"
BUCKET="photoviewer-9876543210"
LAMBDA_MAIN="photoviewer-lambda"
LAMBDA_AUTH="photoviewer-authorizer"

PASS=0
FAIL=0
WARN=0

green()  { echo -e "\033[0;32m✓ $*\033[0m"; }
red()    { echo -e "\033[0;31m✗ $*\033[0m"; }
yellow() { echo -e "\033[0;33m⚠ $*\033[0m"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CS 55D — Week 6 Pre-flight Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Lambda main function ────────────────────────────────────────────────────
echo "[ 1/6 ] Main Lambda function"
if aws lambda get-function \
    --function-name "$LAMBDA_MAIN" \
    --region "$REGION" \
    --query 'Configuration.FunctionName' \
    --output text > /dev/null 2>&1; then
  green "  $LAMBDA_MAIN exists"
  PASS=$((PASS+1))
else
  red "  $LAMBDA_MAIN not found — complete Week 5 Step 2 before continuing"
  FAIL=$((FAIL+1))
fi

# ── 2. Lambda authorizer function ─────────────────────────────────────────────
echo "[ 2/6 ] Lambda authorizer function"
if aws lambda get-function \
    --function-name "$LAMBDA_AUTH" \
    --region "$REGION" \
    --query 'Configuration.FunctionName' \
    --output text > /dev/null 2>&1; then
  green "  $LAMBDA_AUTH exists"
  PASS=$((PASS+1))
else
  red "  $LAMBDA_AUTH not found — complete Week 5 Step 7 before continuing"
  FAIL=$((FAIL+1))
fi

# ── 3. DynamoDB table + item count ────────────────────────────────────────────
echo "[ 3/6 ] DynamoDB table and items"
COUNT=$(aws dynamodb scan \
    --region "$REGION" \
    --table-name "$TABLE" \
    --select COUNT \
    --query 'Count' \
    --output text 2>/dev/null || echo "ERROR")

if [ "$COUNT" = "ERROR" ]; then
  red "  Table $TABLE not found — run the Week 5 pre-flight to create and seed it"
  FAIL=$((FAIL+1))
elif [ "$COUNT" -ge 5 ]; then
  green "  Table $TABLE exists with $COUNT items"
  PASS=$((PASS+1))
else
  yellow "  Table exists but only $COUNT items (expected ≥5) — re-seed with week5-preflight.sh"
  WARN=$((WARN+1))
fi

# ── 4. S3 bucket + photo files ────────────────────────────────────────────────
echo "[ 4/6 ] S3 bucket and photo files"
PHOTO_COUNT=$(aws s3 ls "s3://$BUCKET/photos/" \
    --region "$REGION" 2>/dev/null | wc -l || echo "0")

if [ "$PHOTO_COUNT" -ge 5 ]; then
  green "  Bucket $BUCKET has $PHOTO_COUNT files under photos/"
  PASS=$((PASS+1))
else
  yellow "  Bucket $BUCKET has fewer than 5 photo files — upload may be incomplete"
  WARN=$((WARN+1))
fi

# ── 5. CloudFront distribution ────────────────────────────────────────────────
echo "[ 5/6 ] CloudFront distribution"
CF_DOMAIN=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?contains(Origins.Items[].DomainName, '$BUCKET')].DomainName | [0]" \
    --output text 2>/dev/null || echo "None")

if [ "$CF_DOMAIN" != "None" ] && [ -n "$CF_DOMAIN" ]; then
  green "  CloudFront distribution found: $CF_DOMAIN"
  PASS=$((PASS+1))
  echo ""
  echo "  Your CloudFront domain: https://$CF_DOMAIN"
  echo "  Use this as YOUR_CLOUDFRONT_DOMAIN in app.js"
else
  red "  No CloudFront distribution found pointing to $BUCKET"
  FAIL=$((FAIL+1))
fi

# ── 6. WAF Web ACL attached to CloudFront ─────────────────────────────────────
echo "[ 6/6 ] WAF Web ACL"
WAF_COUNT=$(aws wafv2 list-web-acls \
    --scope CLOUDFRONT \
    --region us-east-1 \
    --query 'length(WebACLs)' \
    --output text 2>/dev/null || echo "0")

if [ "$WAF_COUNT" -ge 1 ]; then
  green "  WAF Web ACL found (CLOUDFRONT scope)"
  PASS=$((PASS+1))
else
  yellow "  No WAF Web ACL found — complete Week 5 Step 13 before continuing"
  WARN=$((WARN+1))
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS passed · $WARN warnings · $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "  ✗ Fix the failed checks before starting Week 6."
  echo ""
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo ""
  echo "  ⚠ Warnings found — review before continuing."
  echo ""
else
  echo ""
  echo "  ✓ All checks passed — ready to start Week 6."
  echo ""
fi
