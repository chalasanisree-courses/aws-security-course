#!/bin/bash
# ============================================================
# CS 55D — Week 12 Pre-flight Check
# Verifies the environment is intact before starting
# the Security Governance lab.
#
# Run from CloudShell:
#   bash aws-security-course/photoviewer/week12/week12-preflight.sh
# ============================================================

set -euo pipefail
PASS=0; WARN=0; FAIL=0
pass() { echo "  ✅ $1"; ((PASS++)); }
warn() { echo "  ⚠️  $1"; ((WARN++)); }
fail() { echo "  ❌ $1"; ((FAIL++)); }

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  CS 55D — Week 12 Pre-flight Check           ║"
echo "║  Security Governance                          ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 1. AWS Organizations ──
echo "1. AWS Organizations"
ORG_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text 2>/dev/null || echo "NONE")
if [ "$ORG_ID" != "NONE" ]; then
  pass "Organization exists: $ORG_ID"
else
  fail "No organization found — was it created in the Identity Center lab?"
fi

# ── 2. OUs ──
echo ""
echo "2. Organizational Units"
if [ "$ORG_ID" != "NONE" ]; then
  ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text 2>/dev/null || echo "NONE")
  if [ "$ROOT_ID" != "NONE" ]; then
    OUS=$(aws organizations list-organizational-units-for-parent --parent-id "$ROOT_ID" --query 'OrganizationalUnits[].Name' --output text 2>/dev/null || echo "")
    if echo "$OUS" | grep -qi "production"; then
      pass "Production OU exists"
    else
      fail "Production OU not found under Root"
    fi
    if echo "$OUS" | grep -qi "staging"; then
      pass "Staging OU exists"
    else
      warn "Staging OU not found (created in Identity Center lab)"
    fi
  else
    fail "Could not find organization root"
  fi
else
  fail "Skipping OU check — no organization"
fi

# ── 3. Identity Center ──
echo ""
echo "3. Identity Center"
SSO_INSTANCE=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text 2>/dev/null || echo "NONE")
if [ "$SSO_INSTANCE" != "NONE" ] && [ "$SSO_INSTANCE" != "None" ]; then
  pass "Identity Center instance exists"
else
  warn "Identity Center not found — was it set up in the Identity Center lab?"
fi

# ── 4. CloudTrail ──
echo ""
echo "4. CloudTrail"
TRAIL_STATUS=$(aws cloudtrail get-trail-status --name $(aws cloudtrail describe-trails --query 'trailList[0].Name' --output text 2>/dev/null || echo "none") --query 'IsLogging' --output text 2>/dev/null || echo "NONE")
if [ "$TRAIL_STATUS" = "True" ]; then
  pass "CloudTrail is active and logging"
elif [ "$TRAIL_STATUS" = "False" ]; then
  fail "CloudTrail exists but logging is STOPPED — re-enable before starting"
else
  warn "Could not check CloudTrail status"
fi

# ── 5. SCPs status ──
echo ""
echo "5. Service Control Policies"
SCP_STATUS=$(aws organizations describe-organization --query 'Organization.AvailablePolicyTypes[?Type==`SERVICE_CONTROL_POLICY`].Status' --output text 2>/dev/null || echo "NONE")
if [ "$SCP_STATUS" = "ENABLED" ]; then
  pass "SCPs are already enabled"
else
  warn "SCPs not yet enabled — you will enable them in Step 1 of the lab"
fi

# ── 6. Prior week services (spot check) ──
echo ""
echo "6. Prior week services (spot check)"
# Lambda
LAMBDA_COUNT=$(aws lambda list-functions --query 'length(Functions)' --output text 2>/dev/null || echo "0")
if [ "$LAMBDA_COUNT" -gt 0 ]; then
  pass "Lambda functions exist ($LAMBDA_COUNT found)"
else
  warn "No Lambda functions found"
fi

# S3 bucket
BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'photoviewer')].Name" --output text 2>/dev/null || echo "")
if [ -n "$BUCKET" ]; then
  pass "PhotoViewer S3 bucket exists: $BUCKET"
else
  warn "No PhotoViewer S3 bucket found"
fi

# ── Summary ──
echo ""
echo "════════════════════════════════════════════════"
echo "  Results: $PASS passed, $WARN warnings, $FAIL failures"
echo "════════════════════════════════════════════════"
if [ $FAIL -gt 0 ]; then
  echo ""
  echo "  ❌ Address failures before starting the lab."
elif [ $WARN -gt 0 ]; then
  echo ""
  echo "  ⚠️  Warnings are informational — you can proceed."
else
  echo ""
  echo "  ✅ All checks passed. Ready for Week 12."
fi
echo ""
