#!/bin/bash
# ============================================================
# CS 55D — Week 9 Pre-flight Check
# Run this before starting the Week 9 lab to verify your
# Week 8 environment is in the correct state.
#
# Usage (from CloudShell):
#   bash aws-security-course/photoviewer/week09/week9-preflight.sh
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
echo "  CS 55D — Week 9 Pre-flight Check"
echo "========================================"
echo ""

# ── 1. KMS infra key ─────────────────────────────────────────
echo "[ KMS — photoviewer-infra-key ]"
INFRA_KEY_INFO=$(aws kms describe-key --key-id alias/photoviewer-infra-key \
  --region $REGION \
  --query "KeyMetadata.[KeyId,Arn,KeyState]" \
  --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$INFRA_KEY_INFO" ]; then
  INFRA_KEY_ID=$(echo "$INFRA_KEY_INFO" | awk '{print $1}')
  INFRA_KEY_ARN=$(echo "$INFRA_KEY_INFO" | awk '{print $2}')
  INFRA_KEY_STATE=$(echo "$INFRA_KEY_INFO" | awk '{print $3}')

  if [ "$INFRA_KEY_STATE" = "Enabled" ]; then
    green "photoviewer-infra-key exists and is Enabled"
    echo "     ARN: $INFRA_KEY_ARN"
  else
    fail "photoviewer-infra-key exists but state is $INFRA_KEY_STATE"
  fi
else
  fail "photoviewer-infra-key not found — complete Week 8 before continuing"
  INFRA_KEY_ARN=""
fi
echo ""

# ── 2. KMS data key ──────────────────────────────────────────
echo "[ KMS — photoviewer-data-key ]"
DATA_KEY_INFO=$(aws kms describe-key --key-id alias/photoviewer-data-key \
  --region $REGION \
  --query "KeyMetadata.[KeyId,Arn,KeyState]" \
  --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$DATA_KEY_INFO" ]; then
  DATA_KEY_ID=$(echo "$DATA_KEY_INFO" | awk '{print $1}')
  DATA_KEY_ARN=$(echo "$DATA_KEY_INFO" | awk '{print $2}')
  DATA_KEY_STATE=$(echo "$DATA_KEY_INFO" | awk '{print $3}')

  if [ "$DATA_KEY_STATE" = "Enabled" ]; then
    green "photoviewer-data-key exists and is Enabled"
    echo "     ARN: $DATA_KEY_ARN"
  else
    fail "photoviewer-data-key exists but state is $DATA_KEY_STATE"
  fi
else
  fail "photoviewer-data-key not found — complete Week 8 before continuing"
  DATA_KEY_ARN=""
fi
echo ""

# ── 3. S3 bucket encryption ──────────────────────────────────
echo "[ S3 bucket — data key encryption ]"
BUCKET=""
for b in $(aws s3api list-buckets --query "Buckets[].Name" --output text 2>/dev/null); do
  COUNT=$(aws s3 ls s3://$b/photos/ --region $REGION 2>/dev/null | grep -c "\." || true)
  if [ "$COUNT" -gt 0 ]; then
    BUCKET=$b
    break
  fi
done

if [ -n "$BUCKET" ]; then
  S3_KMS_KEY=$(aws s3api get-bucket-encryption --bucket $BUCKET \
    --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID" \
    --output text 2>/dev/null)

  if [ -n "$S3_KMS_KEY" ] && [ "$S3_KMS_KEY" != "None" ]; then
    if [ -n "$DATA_KEY_ID" ] && echo "$S3_KMS_KEY" | grep -q "$DATA_KEY_ID"; then
      green "Bucket '$BUCKET' encrypted with data key"
    else
      warn "Bucket '$BUCKET' encrypted with KMS but key may not match data key"
      echo "     Found: $S3_KMS_KEY"
    fi
  else
    fail "Bucket '$BUCKET' not encrypted with customer-managed KMS key"
  fi
else
  fail "No S3 bucket found with a photos/ folder"
fi
echo ""

# ── 4. DynamoDB encryption ────────────────────────────────────
echo "[ DynamoDB — $TABLE encryption ]"
DYNAMO_KMS=$(aws dynamodb describe-table --table-name $TABLE --region $REGION \
  --query "Table.SSEDescription.[SSEType,KMSMasterKeyArn]" \
  --output text 2>/dev/null)

DYNAMO_SSE_TYPE=$(echo "$DYNAMO_KMS" | awk '{print $1}')
DYNAMO_KMS_ARN=$(echo "$DYNAMO_KMS" | awk '{print $2}')

if [ "$DYNAMO_SSE_TYPE" = "KMS" ]; then
  if [ -n "$DATA_KEY_ID" ] && echo "$DYNAMO_KMS_ARN" | grep -q "$DATA_KEY_ID"; then
    green "Table encrypted with data key"
  else
    warn "Table encrypted with KMS but key may not match data key"
    echo "     Found: $DYNAMO_KMS_ARN"
  fi
else
  fail "Table not encrypted with customer-managed KMS key (SSE type: $DYNAMO_SSE_TYPE)"
fi
echo ""

# ── 5. Secrets Manager encryption ────────────────────────────
echo "[ Secrets Manager — $SECRET_NAME ]"
SECRET_KMS=$(aws secretsmanager describe-secret \
  --secret-id $SECRET_NAME --region $REGION \
  --query "KmsKeyId" --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$SECRET_KMS" ] && [ "$SECRET_KMS" != "None" ]; then
  if [ -n "$INFRA_KEY_ID" ] && echo "$SECRET_KMS" | grep -q "$INFRA_KEY_ID"; then
    green "Secret encrypted with infra key"
  else
    warn "Secret encrypted with KMS but key may not match infra key"
    echo "     Found: $SECRET_KMS"
  fi
else
  fail "Secret not encrypted with customer-managed KMS key"
fi
echo ""

# ── 6. Photo Viewer loads ─────────────────────────────────────
echo "[ Photo Viewer — CloudFront ]"
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
" 2>/dev/null)

  if [ -n "$CF_DOMAIN" ]; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$CF_DOMAIN/" 2>/dev/null)
    if [ "$HTTP_STATUS" = "200" ]; then
      green "Photo Viewer loads (HTTP $HTTP_STATUS)"
      echo "     URL: https://$CF_DOMAIN"
    else
      warn "Photo Viewer returned HTTP $HTTP_STATUS (expected 200)"
    fi
  else
    warn "No CloudFront distribution found for bucket '$BUCKET'"
  fi
else
  echo "  -  Skipped — no S3 bucket found"
fi
echo ""

# ── 7. Organizations (check if already enabled) ──────────────
echo "[ AWS Organizations ]"
ORG_ID=$(aws organizations describe-organization \
  --query "Organization.Id" --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$ORG_ID" ] && [ "$ORG_ID" != "None" ]; then
  warn "Organizations already enabled ($ORG_ID) — from a previous attempt?"
else
  echo "  -  Not enabled yet — will be created in Step 1 of the lab"
fi
echo ""

# ── 8. Identity Center (check if already enabled) ────────────
echo "[ IAM Identity Center ]"
IC_INSTANCE=$(aws sso-admin list-instances \
  --query "Instances[0].InstanceArn" --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$IC_INSTANCE" ] && [ "$IC_INSTANCE" != "None" ]; then
  warn "Identity Center already enabled — from a previous attempt?"
else
  echo "  -  Not enabled yet — will be created in Step 2 of the lab"
fi
echo ""

# ── Key ARNs for reference ────────────────────────────────────
echo "========================================"
echo "  Key ARNs (copy these for the lab)"
echo "========================================"
echo ""
if [ -n "$INFRA_KEY_ARN" ]; then
  echo "  Infra key: $INFRA_KEY_ARN"
else
  echo "  Infra key: (not found)"
fi
if [ -n "$DATA_KEY_ARN" ]; then
  echo "  Data key:  $DATA_KEY_ARN"
else
  echo "  Data key:  (not found)"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: $FAIL error(s) — fix before starting Week 9"
elif [ "$WARN" -gt 0 ]; then
  echo "  RESULT: $WARN warning(s) — review items above before continuing"
else
  echo "  RESULT: All checks passed — ready to start Week 9"
fi
echo "========================================"
echo ""
