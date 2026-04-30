#!/bin/bash
# ============================================================
# CS 55D — Week 10 Pre-flight Check
# Run this before starting the Week 10 lab to verify your
# Week 9 environment is in the correct state.
#
# Usage (from CloudShell):
#   bash aws-security-course/photoviewer/week10/week10-preflight.sh
# ============================================================

REGION="us-east-1"
TABLE="photoviewer-photos"
SECRET_NAME="photoviewer/origin-verify-secret"
LAMBDA_NAME="photoviewer-lambda"
AUTHORIZER_NAME="photoviewer-authorizer"
PASS=0
WARN=0
FAIL=0

green() { echo "  ✓  $1"; PASS=$((PASS+1)); }
warn()  { echo "  ⚠  $1"; WARN=$((WARN+1)); }
fail()  { echo "  ✗  $1"; FAIL=$((FAIL+1)); }

echo ""
echo "========================================"
echo "  CS 55D — Week 10 Pre-flight Check"
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

# ── 6. Lambda functions ──────────────────────────────────────
echo "[ Lambda functions ]"
LAMBDA_ARN=$(aws lambda get-function --function-name $LAMBDA_NAME --region $REGION \
  --query "Configuration.FunctionArn" --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$LAMBDA_ARN" ] && [ "$LAMBDA_ARN" != "None" ]; then
  # Check PHOTO_BUCKET env var exists
  PHOTO_BUCKET_VAR=$(aws lambda get-function-configuration \
    --function-name $LAMBDA_NAME --region $REGION \
    --query "Environment.Variables.PHOTO_BUCKET" --output text 2>/dev/null)

  if [ -n "$PHOTO_BUCKET_VAR" ] && [ "$PHOTO_BUCKET_VAR" != "None" ]; then
    green "$LAMBDA_NAME exists (PHOTO_BUCKET=$PHOTO_BUCKET_VAR)"
  else
    fail "$LAMBDA_NAME exists but PHOTO_BUCKET env var is missing"
  fi
else
  fail "$LAMBDA_NAME not found"
fi

AUTH_ARN=$(aws lambda get-function --function-name $AUTHORIZER_NAME --region $REGION \
  --query "Configuration.FunctionArn" --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$AUTH_ARN" ] && [ "$AUTH_ARN" != "None" ]; then
  green "$AUTHORIZER_NAME exists"
else
  warn "$AUTHORIZER_NAME not found — may have a different name"
fi
echo ""

# ── 7. Photo Viewer loads ─────────────────────────────────────
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

# ── 8. Organizations ─────────────────────────────────────────
echo "[ AWS Organizations ]"
ORG_ID=$(aws organizations describe-organization \
  --query "Organization.Id" --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$ORG_ID" ] && [ "$ORG_ID" != "None" ]; then
  green "Organizations enabled ($ORG_ID)"
else
  fail "Organizations not enabled — complete Week 9 before continuing"
fi
echo ""

# ── 9. Identity Center ───────────────────────────────────────
echo "[ IAM Identity Center ]"
IC_INSTANCE=$(aws sso-admin list-instances \
  --query "Instances[0].InstanceArn" --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$IC_INSTANCE" ] && [ "$IC_INSTANCE" != "None" ]; then
  green "Identity Center enabled"
else
  fail "Identity Center not enabled — complete Week 9 before continuing"
fi
echo ""

# ── 10. SNS topic (needed for CloudWatch alarms) ─────────────
echo "[ SNS — notification topic ]"
SNS_TOPICS=$(aws sns list-topics --region $REGION \
  --query "Topics[].TopicArn" --output text 2>/dev/null)

if [ -n "$SNS_TOPICS" ]; then
  TOPIC_COUNT=$(echo "$SNS_TOPICS" | wc -w)
  # Find first topic and show it
  FIRST_TOPIC=$(echo "$SNS_TOPICS" | awk '{print $1}')
  TOPIC_NAME=$(echo "$FIRST_TOPIC" | awk -F: '{print $NF}')
  green "SNS topic found: $TOPIC_NAME"
  if [ "$TOPIC_COUNT" -gt 1 ]; then
    echo "     ($TOPIC_COUNT topics found — use the one from Week 1 for alarm notifications)"
  fi

  # Check if topic has subscriptions
  SUB_COUNT=$(aws sns list-subscriptions-by-topic --topic-arn "$FIRST_TOPIC" --region $REGION \
    --query "length(Subscriptions)" --output text 2>/dev/null)
  if [ "$SUB_COUNT" -gt 0 ] 2>/dev/null; then
    green "Topic has $SUB_COUNT subscription(s) — alarm emails will be delivered"
  else
    warn "Topic has no confirmed subscriptions — you may not receive alarm emails"
  fi
else
  fail "No SNS topics found — create one before setting up CloudWatch alarms"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: $FAIL error(s) — fix before starting Week 10"
elif [ "$WARN" -gt 0 ]; then
  echo "  RESULT: All critical checks passed, $WARN warning(s) — review items above"
else
  echo "  RESULT: All checks passed — ready to start Week 10"
fi
echo "  ($PASS passed, $WARN warnings, $FAIL errors)"
echo "========================================"
echo ""
