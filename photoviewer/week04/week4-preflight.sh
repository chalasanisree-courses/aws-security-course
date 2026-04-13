#!/bin/bash
# ============================================================
# CS 55D — Week 4 Pre-flight Check
# Run this before starting the Week 4 lab to verify your
# Week 3 environment is in the correct state.
#
# Usage (from CloudShell):
#   bash aws-security-course/photoviewer/week04/week4-preflight.sh
# ============================================================

REGION="us-east-1"
TABLE="photoviewer-photos"
WARN=0
FAIL=0

green() { echo "  ✓  $1"; }
warn()  { echo "  ⚠  $1"; WARN=$((WARN+1)); }
fail()  { echo "  ✗  $1"; FAIL=$((FAIL+1)); }

echo ""
echo "========================================"
echo "  CS 55D — Week 4 Pre-flight Check"
echo "========================================"
echo ""

# ── 1. S3 bucket with photos ─────────────────────────────────
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
    warn "Only $PHOTO_COUNT .jpg files found in photos/ — expected 5."
    echo "     Re-upload the photo files from the Week 2/3 lab before proceeding."
  fi
else
  fail "No S3 bucket found with a photos/ folder containing .jpg files."
  echo "     Make sure your Week 2/3 S3 bucket exists and contains photo files."
fi
echo ""

# ── 2. CloudFront distribution ───────────────────────────────
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
    echo "     Use this domain to access your Photo Viewer throughout the lab."
  else
    warn "No CloudFront distribution found pointing to bucket '$BUCKET'."
    echo "     Make sure your Week 3 CloudFront distribution still exists."
  fi
else
  echo "  -  Skipped — no S3 bucket found"
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
  warn "Table '$TABLE' already exists with $ITEM_COUNT items."
  echo "     Week 4 Step 1 creates this table — if it already exists you can skip that step,"
  echo "     but verify it has the correct 5 items before proceeding."
else
  green "Table '$TABLE' does not exist — will be created in Step 1"
fi
echo ""

# ── 4. Leftover expensive resources ──────────────────────────
echo "[ Leftover resources from previous attempts ]"
FOUND_LEFTOVERS=0

# NAT Gateway
NAT=$(aws ec2 describe-nat-gateways --region $REGION \
  --filter "Name=tag:Name,Values=*photoviewer*" "Name=state,Values=available" \
  --query "NatGateways[].NatGatewayId" --output text 2>/dev/null)
if [ -n "$NAT" ]; then
  warn "NAT Gateway still running: $NAT (~\$32/month) — delete before starting"
  FOUND_LEFTOVERS=1
fi

# EC2
INSTANCES=$(aws ec2 describe-instances --region $REGION \
  --filters "Name=tag:Name,Values=photoviewer-ec2" \
            "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text 2>/dev/null)
if [ -n "$INSTANCES" ]; then
  warn "EC2 instance still exists: $INSTANCES — terminate before starting"
  FOUND_LEFTOVERS=1
fi

# ALB
ALBS=$(aws elbv2 describe-load-balancers --region $REGION \
  --query "LoadBalancers[?contains(LoadBalancerName,'photoviewer')].LoadBalancerName" \
  --output text 2>/dev/null)
if [ -n "$ALBS" ]; then
  warn "ALB still exists: $ALBS — delete before starting"
  FOUND_LEFTOVERS=1
fi

if [ "$FOUND_LEFTOVERS" -eq 0 ]; then
  green "No leftover expensive resources found — ready to start"
fi
echo ""

# ── Summary ──────────────────────────────────────────────────
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: $FAIL error(s) found — resolve before proceeding"
elif [ "$WARN" -gt 0 ]; then
  echo "  RESULT: $WARN warning(s) — review items above before proceeding"
else
  echo "  RESULT: All checks passed — ready to start Week 4"
fi
echo "========================================"
echo ""
