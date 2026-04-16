#!/bin/bash
# ============================================================
# CS 55D — Week 6 Pre-flight Check
# Run this before starting the Week 6 lab to verify your
# Week 5 environment is in the correct state.
#
# Usage (from CloudShell):
#   bash aws-security-course/photoviewer/week06/week6-preflight.sh
# ============================================================

REGION="us-east-1"
TABLE="photoviewer-photos"
BUCKET="photoviewer-9876543210"
PASS=0
WARN=0
FAIL=0

green() { echo "  ✓  $1"; PASS=$((PASS+1)); }
warn()  { echo "  ⚠  $1"; WARN=$((WARN+1)); }
fail()  { echo "  ✗  $1"; FAIL=$((FAIL+1)); }

echo ""
echo "========================================"
echo "  CS 55D — Week 6 Pre-flight Check"
echo "========================================"
echo ""

# ── 1. Lambda main function ───────────────────────────────────
echo "[ Lambda — photoviewer-lambda ]"
STATUS=$(aws lambda get-function \
  --function-name photoviewer-lambda \
  --region $REGION \
  --query "Configuration.State" \
  --output text 2>/dev/null)
if [ "$STATUS" = "Active" ]; then
  green "photoviewer-lambda exists and is Active"
else
  fail "photoviewer-lambda not found — complete Week 5 Step 2 before continuing"
fi
echo ""

# ── 2. Lambda authorizer ──────────────────────────────────────
echo "[ Lambda — photoviewer-authorizer ]"
STATUS=$(aws lambda get-function \
  --function-name photoviewer-authorizer \
  --region $REGION \
  --query "Configuration.State" \
  --output text 2>/dev/null)
if [ "$STATUS" = "Active" ]; then
  green "photoviewer-authorizer exists and is Active"
else
  fail "photoviewer-authorizer not found — complete Week 5 Step 7 before continuing"
fi
echo ""

# ── 3. DynamoDB table ─────────────────────────────────────────
echo "[ DynamoDB table: $TABLE ]"
TABLE_STATUS=$(aws dynamodb describe-table --region $REGION \
  --table-name $TABLE \
  --query "Table.TableStatus" \
  --output text 2>/dev/null)

if [ "$TABLE_STATUS" = "ACTIVE" ]; then
  ITEM_COUNT=$(aws dynamodb scan --region $REGION \
    --table-name $TABLE --select COUNT \
    --query Count --output text 2>/dev/null)
  if [ "$ITEM_COUNT" -ge 5 ]; then
    green "Table exists with $ITEM_COUNT items — ready"
  else
    warn "Table exists but only $ITEM_COUNT items (expected ≥5) — re-seed with week5-preflight.sh"
  fi
else
  fail "Table '$TABLE' not found — run week5-preflight.sh to create and seed it"
fi
echo ""

# ── 4. S3 bucket ──────────────────────────────────────────────
echo "[ S3 bucket: $BUCKET ]"
PHOTO_COUNT=$(aws s3 ls s3://$BUCKET/photos/ --region $REGION 2>/dev/null | grep -c "\.jpg" || true)
if [ "$PHOTO_COUNT" -ge 5 ]; then
  green "$PHOTO_COUNT photo files found in $BUCKET/photos/ — ready"
else
  warn "Only $PHOTO_COUNT .jpg files found in $BUCKET/photos/ — expected ≥5"
fi
echo ""

# ── 5. CloudFront distribution ────────────────────────────────
echo "[ CloudFront distribution ]"
CF_DOMAIN=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[].{Domain:DomainName,Origins:Origins.Items[].DomainName}" \
  --output json 2>/dev/null | \
  python3 -c "
import json,sys
items=json.load(sys.stdin)
for i in items:
    if any('$BUCKET' in o for o in i.get('Origins',[])):
        print(i['Domain'])
        break
")
if [ -n "$CF_DOMAIN" ]; then
  green "Distribution found: $CF_DOMAIN"
  echo ""
  echo "     Your CloudFront domain: https://$CF_DOMAIN"
  echo "     Use this as YOUR_CLOUDFRONT_DOMAIN in app.js"
else
  fail "No CloudFront distribution found pointing to bucket '$BUCKET'"
  echo "     Make sure your Week 3 CloudFront distribution still exists"
fi
echo ""

# ── 6. WAF Web ACL ────────────────────────────────────────────
echo "[ WAF Web ACL ]"
WAF_COUNT=$(aws wafv2 list-web-acls \
  --scope CLOUDFRONT \
  --region us-east-1 \
  --query "length(WebACLs)" \
  --output text 2>/dev/null)
if [ "$WAF_COUNT" -ge 1 ] 2>/dev/null; then
  green "WAF Web ACL found (CLOUDFRONT scope)"
else
  warn "No WAF Web ACL found — complete Week 5 Step 13 before continuing"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: $FAIL error(s) — fix before starting Week 6"
elif [ "$WARN" -gt 0 ]; then
  echo "  RESULT: $WARN warning(s) — review items above before continuing"
else
  echo "  RESULT: All checks passed — ready to start Week 6"
fi
echo "========================================"
echo ""
