#!/bin/bash
# ============================================================
# CS 55D — Week 8 Pre-flight Check
# Run this before starting the Week 8 lab to verify your
# Week 7 environment is in the correct state.
#
# Usage (from CloudShell):
#   bash aws-security-course/photoviewer/week08/week8-preflight.sh
# ============================================================

REGION="us-east-1"
TABLE="photoviewer-photos"
SECRET_NAME="photoviewer/origin-verify-secret"
PASS=0
WARN=0
FAIL=0

green() { echo "  ✓  $1"; PASS=$((PASS+1)); }
warn()  { echo "  ⚠  $1"; WARN=$((WARN+1)); }
fail()  { echo "  ✗  $1"; FAIL=$((FAIL+1)); }

echo ""
echo "========================================"
echo "  CS 55D — Week 8 Pre-flight Check"
echo "========================================"
echo ""

# ── 1. Lambda main function ───────────────────────────────────
echo "[ Lambda — photoviewer-lambda ]"
LAMBDA_ROLE=$(aws lambda get-function \
  --function-name photoviewer-lambda \
  --region $REGION \
  --query "Configuration.[State,Role]" \
  --output text 2>/dev/null)
STATUS=$(echo "$LAMBDA_ROLE" | awk '{print $1}')
ROLE_ARN=$(echo "$LAMBDA_ROLE" | awk '{print $2}')
if [ "$STATUS" = "Active" ]; then
  green "photoviewer-lambda exists and is Active"
  echo "     Execution role: $ROLE_ARN"
  echo "     (You will need this role when creating the data key)"
else
  fail "photoviewer-lambda not found — complete Week 5 before continuing"
fi
echo ""

# ── 2. Lambda authorizer ──────────────────────────────────────
echo "[ Lambda — photoviewer-authorizer ]"
AUTH_ROLE=$(aws lambda get-function \
  --function-name photoviewer-authorizer \
  --region $REGION \
  --query "Configuration.[State,Role]" \
  --output text 2>/dev/null)
AUTH_STATUS=$(echo "$AUTH_ROLE" | awk '{print $1}')
AUTH_ROLE_ARN=$(echo "$AUTH_ROLE" | awk '{print $2}')
if [ "$AUTH_STATUS" = "Active" ]; then
  green "photoviewer-authorizer exists and is Active"
  echo "     Execution role: $AUTH_ROLE_ARN"
  echo "     (You will need this role when creating the infra key)"
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
  
  # Check current encryption
  ENCRYPTION=$(aws dynamodb describe-table --region $REGION \
    --table-name $TABLE \
    --query "Table.SSEDescription.SSEType" \
    --output text 2>/dev/null)
  if [ "$ENCRYPTION" = "KMS" ]; then
    warn "Table already encrypted with KMS — verify this is from a previous attempt"
  else
    echo "     Current encryption: AWS-owned (default) — will switch to customer-managed in this lab"
  fi
else
  fail "Table '$TABLE' not found"
fi
echo ""

# ── 4. S3 bucket — discover dynamically ─────────────────────
echo "[ S3 bucket with photos ]"
BUCKET=""
PHOTO_COUNT=0
for b in $(aws s3api list-buckets --query "Buckets[].Name" --output text 2>/dev/null); do
  COUNT=$(aws s3 ls s3://$b/photos/ --region $REGION 2>/dev/null | grep -c "\.jpg" || true)
  if [ "$COUNT" -gt 0 ]; then
    BUCKET=$b
    PHOTO_COUNT=$COUNT
    break
  fi
done

if [ -n "$BUCKET" ]; then
  green "Found bucket: $BUCKET"
  
  # Check current encryption
  S3_ENC=$(aws s3api get-bucket-encryption --bucket $BUCKET \
    --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm" \
    --output text 2>/dev/null)
  if [ "$S3_ENC" = "aws:kms" ]; then
    warn "Bucket already using SSE-KMS — verify this is from a previous attempt"
  else
    echo "     Current encryption: $S3_ENC (default) — will switch to SSE-KMS in this lab"
  fi
else
  fail "No S3 bucket found with a photos/ folder containing .jpg files"
fi
echo ""

# ── 5. CloudFront distribution ────────────────────────────────
echo "[ CloudFront distribution ]"
if [ -n "$BUCKET" ]; then
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
else
  echo "  -  Skipped — no S3 bucket found"
fi
echo ""

# ── 6. Cognito User Pool ─────────────────────────────────────
echo "[ Cognito User Pool ]"
POOL_ID=$(aws cognito-idp list-user-pools --max-results 10 --region $REGION \
  --query "UserPools[0].Id" --output text 2>/dev/null)

if [ -n "$POOL_ID" ] && [ "$POOL_ID" != "None" ]; then
  green "User Pool found: $POOL_ID"

  # Check for free and premium groups
  aws cognito-idp list-groups --user-pool-id $POOL_ID --region $REGION \
    --query "Groups[].GroupName" --output json > /tmp/pv_groups.json 2>/dev/null

  if grep -q '"free"' /tmp/pv_groups.json 2>/dev/null; then
    green "Group 'free' exists"
  else
    fail "Group 'free' not found in User Pool"
  fi

  if grep -q '"premium"' /tmp/pv_groups.json 2>/dev/null; then
    green "Group 'premium' exists"
  else
    fail "Group 'premium' not found in User Pool"
  fi

  rm -f /tmp/pv_groups.json
else
  fail "No Cognito User Pool found"
fi
echo ""

# ── 7. Secrets Manager ───────────────────────────────────────
echo "[ Secrets Manager: $SECRET_NAME ]"
SECRET_ENC=$(aws secretsmanager describe-secret \
  --secret-id $SECRET_NAME \
  --region $REGION \
  --query "[Name,KmsKeyId]" --output text 2>/dev/null)

SECRET_EXISTS=$(echo "$SECRET_ENC" | awk '{print $1}')
SECRET_KEY=$(echo "$SECRET_ENC" | awk '{print $2}')

if [ "$SECRET_EXISTS" = "$SECRET_NAME" ]; then
  green "Secret '$SECRET_NAME' exists"
  if [ -n "$SECRET_KEY" ] && [ "$SECRET_KEY" != "None" ]; then
    warn "Secret already using custom KMS key: $SECRET_KEY — verify this is from a previous attempt"
  else
    echo "     Current encryption: AWS-managed (default) — will switch to customer-managed in this lab"
  fi
else
  fail "Secret '$SECRET_NAME' not found — complete Week 6 before continuing"
fi
echo ""

# ── 8. PHOTO_BUCKET env var ───────────────────────────────────
echo "[ Lambda environment: PHOTO_BUCKET ]"
PHOTO_BUCKET=$(aws lambda get-function-configuration \
  --function-name photoviewer-lambda \
  --region $REGION \
  --query "Environment.Variables.PHOTO_BUCKET" \
  --output text 2>/dev/null)

if [ -n "$PHOTO_BUCKET" ] && [ "$PHOTO_BUCKET" != "None" ]; then
  green "PHOTO_BUCKET is set: $PHOTO_BUCKET"
else
  fail "PHOTO_BUCKET environment variable not set — complete Week 7 Step 11 before continuing"
fi
echo ""

# ── 9. Existing KMS keys ─────────────────────────────────────
echo "[ Existing KMS keys ]"
INFRA_KEY=$(aws kms describe-key --key-id alias/photoviewer-infra-key \
  --region $REGION --query "KeyMetadata.KeyId" --output text 2>/dev/null)
DATA_KEY=$(aws kms describe-key --key-id alias/photoviewer-data-key \
  --region $REGION --query "KeyMetadata.KeyId" --output text 2>/dev/null)

if [ -n "$INFRA_KEY" ] && [ "$INFRA_KEY" != "None" ]; then
  warn "photoviewer-infra-key already exists ($INFRA_KEY) — from a previous attempt?"
else
  echo "  -  No photoviewer-infra-key found — will be created in Step 1"
fi

if [ -n "$DATA_KEY" ] && [ "$DATA_KEY" != "None" ]; then
  warn "photoviewer-data-key already exists ($DATA_KEY) — from a previous attempt?"
else
  echo "  -  No photoviewer-data-key found — will be created in Step 2"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: $FAIL error(s) — fix before starting Week 8"
elif [ "$WARN" -gt 0 ]; then
  echo "  RESULT: $WARN warning(s) — review items above before continuing"
else
  echo "  RESULT: All checks passed — ready to start Week 8"
fi
echo "========================================"
echo ""
