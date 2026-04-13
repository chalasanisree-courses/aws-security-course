#!/bin/bash
# ============================================================
# CS 55D — Week 3 Pre-flight Check
# Run this before starting the Week 3 lab to verify your
# Week 2 environment is in the correct state.
#
# Usage (from CloudShell):
#   bash aws-security-course/photoviewer/week03/week3-preflight.sh
# ============================================================

REGION="us-east-1"
WARN=0
FAIL=0

green() { echo "  ✓  $1"; }
warn()  { echo "  ⚠  $1"; WARN=$((WARN+1)); }
fail()  { echo "  ✗  $1"; FAIL=$((FAIL+1)); }

echo ""
echo "========================================"
echo "  CS 55D — Week 3 Pre-flight Check"
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
    echo "     Re-upload the photo files from the Week 2 lab before proceeding."
  fi
else
  fail "No S3 bucket found with a photos/ folder containing .jpg files."
  echo "     Complete the Week 2 lab before starting Week 3."
fi
echo ""

# ── 2. S3 website hosting status ─────────────────────────────
echo "[ S3 static website hosting ]"
if [ -n "$BUCKET" ]; then
  WEBSITE=$(aws s3api get-bucket-website --bucket $BUCKET --region $REGION 2>/dev/null)
  if [ -n "$WEBSITE" ]; then
    green "Static website hosting is ON — Step 2 will disable this"
  else
    green "Static website hosting is already disabled"
  fi
fi
echo ""

# ── 3. Block Public Access ────────────────────────────────────
echo "[ S3 Block Public Access ]"
if [ -n "$BUCKET" ]; then
  BPA=$(aws s3api get-public-access-block --bucket $BUCKET --region $REGION \
    --query "PublicAccessBlockConfiguration" --output json 2>/dev/null)
  if [ -n "$BPA" ]; then
    ALL_ON=$(echo $BPA | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if all(d.values()) else 'no')" 2>/dev/null)
    if [ "$ALL_ON" == "yes" ]; then
      green "Block Public Access fully enabled"
    else
      green "Block Public Access not fully enabled — Step 3 will enable this"
    fi
  else
    green "Block Public Access not configured — Step 3 will enable this"
  fi
fi
echo ""

# ── 4. CloudFront distribution — should NOT exist yet ────────
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
" 2>/dev/null)
  if [ -n "$CF_DOMAIN" ]; then
    warn "A CloudFront distribution already exists pointing to $BUCKET: $CF_DOMAIN"
    echo "     Week 3 creates this — if you are redoing the lab, you can reuse it."
    echo "     If this is a fresh attempt, delete the existing distribution first."
  else
    green "No CloudFront distribution found — ready to create one in Step 5"
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
  echo "  RESULT: All checks passed — ready to start Week 3"
fi
echo "========================================"
echo ""
