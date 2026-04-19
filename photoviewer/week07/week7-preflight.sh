#!/bin/bash
# ============================================================
# CS 55D — Week 7 Pre-flight Check
# Run this before starting the Week 7 lab to verify your
# Week 6 environment is in the correct state.
#
# Usage (from CloudShell):
#   bash aws-security-course/photoviewer/week07/week7-preflight.sh
# ============================================================

REGION="us-east-1"
TABLE="photoviewer-photos"
BUCKET="photoviewer-9876543210"
SECRET_NAME="photoviewer/origin-verify-secret"
PASS=0
WARN=0
FAIL=0

green() { echo "  ✓  $1"; PASS=$((PASS+1)); }
warn()  { echo "  ⚠  $1"; WARN=$((WARN+1)); }
fail()  { echo "  ✗  $1"; FAIL=$((FAIL+1)); }

echo ""
echo "========================================"
echo "  CS 55D — Week 7 Pre-flight Check"
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
  fail "photoviewer-lambda not found — complete Week 5 before continuing"
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
  fail "photoviewer-authorizer not found — complete Week 5 before continuing"
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
  green "Table exists with $ITEM_COUNT items"
else
  fail "Table '$TABLE' not found"
fi
echo ""

# ── 4. S3 bucket ──────────────────────────────────────────────
echo "[ S3 bucket: $BUCKET ]"
if aws s3 ls s3://$BUCKET --region $REGION >/dev/null 2>&1; then
  green "Bucket exists"
else
  fail "Bucket '$BUCKET' not found"
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
else
  fail "No CloudFront distribution found pointing to bucket '$BUCKET'"
fi
echo ""

# ── 6. Cognito User Pool ─────────────────────────────────────
echo "[ Cognito User Pool ]"
POOL_ID=$(aws cognito-idp list-user-pools --max-results 10 --region $REGION \
  --query "UserPools[0].Id" --output text 2>/dev/null)

if [ -n "$POOL_ID" ] && [ "$POOL_ID" != "None" ]; then
  green "User Pool found: $POOL_ID"

  # Check for free and premium groups
  GROUPS=$(aws cognito-idp list-groups --user-pool-id $POOL_ID --region $REGION \
    --query "Groups[].GroupName" --output text 2>/dev/null)

  if echo "$GROUPS" | grep -q "free"; then
    green "Group 'free' exists"
  else
    fail "Group 'free' not found in User Pool"
  fi

  if echo "$GROUPS" | grep -q "premium"; then
    green "Group 'premium' exists"
  else
    fail "Group 'premium' not found in User Pool"
  fi
else
  fail "No Cognito User Pool found"
fi
echo ""

# ── 7. Secrets Manager ───────────────────────────────────────
echo "[ Secrets Manager: $SECRET_NAME ]"
SECRET_EXISTS=$(aws secretsmanager describe-secret \
  --secret-id $SECRET_NAME \
  --region $REGION \
  --query "Name" --output text 2>/dev/null)

if [ "$SECRET_EXISTS" = "$SECRET_NAME" ]; then
  green "Secret '$SECRET_NAME' exists"
else
  fail "Secret '$SECRET_NAME' not found — complete Week 6 before continuing"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: $FAIL error(s) — fix before starting Week 7"
elif [ "$WARN" -gt 0 ]; then
  echo "  RESULT: $WARN warning(s) — review items above before continuing"
else
  echo "  RESULT: All checks passed — ready to start Week 7"
fi
echo "========================================"
echo ""
