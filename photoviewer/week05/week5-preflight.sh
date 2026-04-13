#!/bin/bash
# ============================================================
# CS 55D — Week 5 Pre-flight Check
# Run this before starting the Week 5 lab to verify your
# Week 4 environment is in the correct state.
#
# Usage (from CloudShell):
#   bash aws-security-course/photoviewer/week05/week5-preflight.sh
# ============================================================

REGION="us-east-1"
TABLE="photoviewer-photos"
PASS=0
WARN=0
FAIL=0

green()  { echo "  ✓  $1"; }
warn()   { echo "  ⚠  $1"; WARN=$((WARN+1)); }
fail()   { echo "  ✗  $1"; FAIL=$((FAIL+1)); }

echo ""
echo "========================================"
echo "  CS 55D — Week 5 Pre-flight Check"
echo "========================================"
echo ""

# ── 1. EC2 instances ─────────────────────────────────────────
echo "[ EC2 instances ]"
INSTANCES=$(aws ec2 describe-instances --region $REGION \
  --filters "Name=tag:Name,Values=photoviewer-ec2" \
            "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text 2>/dev/null)
if [ -z "$INSTANCES" ]; then
  green "No photoviewer-ec2 instance running — good, EC2 is gone"
else
  warn "EC2 instance still exists: $INSTANCES — delete it in Step 1"
fi
echo ""

# ── 2. ALB ───────────────────────────────────────────────────
echo "[ Load balancers ]"
ALBS=$(aws elbv2 describe-load-balancers --region $REGION \
  --query "LoadBalancers[?contains(LoadBalancerName,'photoviewer')].LoadBalancerName" \
  --output text 2>/dev/null)
if [ -z "$ALBS" ]; then
  green "No photoviewer ALB found — good, ALB is gone"
else
  warn "ALB still exists: $ALBS — delete it in Step 1"
fi
echo ""

# ── 3. DynamoDB table ────────────────────────────────────────
echo "[ DynamoDB table: $TABLE ]"
TABLE_STATUS=$(aws dynamodb describe-table --region $REGION \
  --table-name $TABLE \
  --query "Table.TableStatus" \
  --output text 2>/dev/null)

if [ "$TABLE_STATUS" == "ACTIVE" ]; then
  ITEM_COUNT=$(aws dynamodb scan --region $REGION \
    --table-name $TABLE --select COUNT \
    --query Count --output text 2>/dev/null)
  green "Table exists and is ACTIVE"
  if [ "$ITEM_COUNT" -ge 5 ]; then
    green "$ITEM_COUNT items found — ready"
  else
    warn "Only $ITEM_COUNT items found (expected 5) — seeding now..."
    aws dynamodb batch-write-item --region $REGION --request-items '{
      "photoviewer-photos": [
        {"PutRequest": {"Item": {"photo_id": {"S": "photo-001"}, "s3_key": {"S": "photos/photo1.jpg"}, "is_public": {"BOOL": true}, "owner": {"S": "admin"}, "uploaded_at": {"S": "2024-01-01"}}}},
        {"PutRequest": {"Item": {"photo_id": {"S": "photo-002"}, "s3_key": {"S": "photos/photo2.jpg"}, "is_public": {"BOOL": true}, "owner": {"S": "admin"}, "uploaded_at": {"S": "2024-01-01"}}}},
        {"PutRequest": {"Item": {"photo_id": {"S": "photo-003"}, "s3_key": {"S": "photos/photo3.jpg"}, "is_public": {"BOOL": true}, "owner": {"S": "admin"}, "uploaded_at": {"S": "2024-01-01"}}}},
        {"PutRequest": {"Item": {"photo_id": {"S": "photo-004"}, "s3_key": {"S": "photos/photo4.jpg"}, "is_public": {"BOOL": true}, "owner": {"S": "admin"}, "uploaded_at": {"S": "2024-01-01"}}}},
        {"PutRequest": {"Item": {"photo_id": {"S": "photo-005"}, "s3_key": {"S": "photos/photo5.jpg"}, "is_public": {"BOOL": true}, "owner": {"S": "admin"}, "uploaded_at": {"S": "2024-01-01"}}}}
      ]
    }' > /dev/null 2>&1 && green "Table seeded with 5 items" || fail "Failed to seed table — check IAM permissions"
  fi
else
  warn "Table '$TABLE' not found — creating and seeding now..."
  aws dynamodb create-table --region $REGION \
    --table-name $TABLE \
    --attribute-definitions AttributeName=photo_id,AttributeType=S \
    --key-schema AttributeName=photo_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST > /dev/null 2>&1
  echo "     Waiting for table to become active..."
  aws dynamodb wait table-exists --region $REGION --table-name $TABLE 2>/dev/null
  aws dynamodb batch-write-item --region $REGION --request-items '{
    "photoviewer-photos": [
      {"PutRequest": {"Item": {"photo_id": {"S": "photo-001"}, "s3_key": {"S": "photos/photo1.jpg"}, "is_public": {"BOOL": true}, "owner": {"S": "admin"}, "uploaded_at": {"S": "2024-01-01"}}}},
      {"PutRequest": {"Item": {"photo_id": {"S": "photo-002"}, "s3_key": {"S": "photos/photo2.jpg"}, "is_public": {"BOOL": true}, "owner": {"S": "admin"}, "uploaded_at": {"S": "2024-01-01"}}}},
      {"PutRequest": {"Item": {"photo_id": {"S": "photo-003"}, "s3_key": {"S": "photos/photo3.jpg"}, "is_public": {"BOOL": true}, "owner": {"S": "admin"}, "uploaded_at": {"S": "2024-01-01"}}}},
      {"PutRequest": {"Item": {"photo_id": {"S": "photo-004"}, "s3_key": {"S": "photos/photo4.jpg"}, "is_public": {"BOOL": true}, "owner": {"S": "admin"}, "uploaded_at": {"S": "2024-01-01"}}}},
      {"PutRequest": {"Item": {"photo_id": {"S": "photo-005"}, "s3_key": {"S": "photos/photo5.jpg"}, "is_public": {"BOOL": true}, "owner": {"S": "admin"}, "uploaded_at": {"S": "2024-01-01"}}}}
    ]
  }' > /dev/null 2>&1 && green "Table created and seeded with 5 items" || fail "Failed to create table — check IAM permissions"
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
  echo "     This is the Photo Viewer S3 bucket used throughout the course."
  if [ "$PHOTO_COUNT" -ge 5 ]; then
    green "$PHOTO_COUNT photo files found in photos/ — ready"
  else
    warn "Only $PHOTO_COUNT .jpg files in photos/ — expected 5. Check your S3 bucket."
  fi
else
  fail "No S3 bucket found with a photos/ folder containing .jpg files."
  echo "     Make sure your Week 2/3 S3 bucket still exists and contains photo files."
fi
echo ""

# ── 5. CloudFront distribution ───────────────────────────────
echo "[ CloudFront distribution ]"
if [ -n "$BUCKET" ]; then
  CF_DOMAIN=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?contains(Origins.Items[].DomainName,'$BUCKET')].DomainName | [0]" \
    --output text 2>/dev/null)
  if [ -n "$CF_DOMAIN" ] && [ "$CF_DOMAIN" != "None" ]; then
    green "Distribution found: $CF_DOMAIN"
    echo "     Use this domain to access your Photo Viewer throughout the lab."
  else
    warn "No CloudFront distribution found pointing to bucket '$BUCKET'."
    echo "     Make sure your Week 3 CloudFront distribution still exists."
  fi
else
  echo "  -  Skipped — no S3 bucket found"
fi
echo ""

# ── Summary ──────────────────────────────────────────────────
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: $FAIL error(s) found — resolve before proceeding"
elif [ "$WARN" -gt 0 ]; then
  echo "  RESULT: $WARN warning(s) — review items above before proceeding"
else
  echo "  RESULT: All checks passed — ready to start Week 5"
fi
echo "========================================"
echo ""
