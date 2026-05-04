#!/bin/bash
# ============================================================
# CS 55D — Week 12 Pre-flight Check
# Verifies Week 9/11 environment is ready for the Governance lab.
# Run from CloudShell:
#   bash aws-security-course/photoviewer/week12/week12-preflight.sh
# ============================================================

REGION="us-east-1"
PASS=0; FAIL=0

pass() { echo "  ✅ $1"; ((PASS++)); }
fail() { echo "  ❌ $1"; ((FAIL++)); }
info() { echo "  ℹ️  $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  CS 55D — Week 12 Pre-flight Check                   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Organizations ──────────────────────────────────────────
echo "1. AWS Organizations"
echo "────────────────────────────────────────────────────────"
ORG_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text 2>/dev/null || echo "NONE")
if [ "$ORG_ID" != "NONE" ] && [ -n "$ORG_ID" ]; then
  pass "Organizations enabled (ID: $ORG_ID)"
else
  fail "Organizations not enabled — enable it before starting"
fi

# ── OUs ────────────────────────────────────────────────────
echo ""
echo "2. Organizational Units"
echo "────────────────────────────────────────────────────────"
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text 2>/dev/null || echo "NONE")
if [ "$ROOT_ID" != "NONE" ] && [ -n "$ROOT_ID" ]; then
  pass "Root found: $ROOT_ID"

  PROD_OU=$(aws organizations list-organizational-units-for-parent --parent-id "$ROOT_ID" \
    --query "OrganizationalUnits[?Name=='Production'].Id" --output text 2>/dev/null || echo "")
  if [ -n "$PROD_OU" ] && [ "$PROD_OU" != "None" ]; then
    pass "Production OU found: $PROD_OU"
  else
    fail "Production OU not found — create it under Root before starting"
  fi

  STAGING_OU=$(aws organizations list-organizational-units-for-parent --parent-id "$ROOT_ID" \
    --query "OrganizationalUnits[?Name=='Staging'].Id" --output text 2>/dev/null || echo "")
  if [ -n "$STAGING_OU" ] && [ "$STAGING_OU" != "None" ]; then
    pass "Staging OU found: $STAGING_OU"
  else
    fail "Staging OU not found — create it under Root before starting"
  fi
else
  fail "Could not find organization root"
fi

# ── CloudTrail ─────────────────────────────────────────────
echo ""
echo "3. CloudTrail (needed for management account exemption test)"
echo "────────────────────────────────────────────────────────"
TRAIL_NAME=$(aws cloudtrail describe-trails --region "$REGION" \
  --query 'trailList[0].Name' --output text 2>/dev/null || echo "NONE")
if [ "$TRAIL_NAME" != "NONE" ] && [ "$TRAIL_NAME" != "None" ] && [ -n "$TRAIL_NAME" ]; then
  IS_LOGGING=$(aws cloudtrail get-trail-status --name "$TRAIL_NAME" --region "$REGION" \
    --query 'IsLogging' --output text 2>/dev/null || echo "false")
  if [ "$IS_LOGGING" = "True" ]; then
    pass "CloudTrail trail active: $TRAIL_NAME (logging: on)"
  else
    fail "CloudTrail trail exists but logging is stopped — re-enable logging before starting"
  fi
else
  fail "No CloudTrail trail found — create one before starting (needed for Step 7)"
fi

# ── Identity Center ────────────────────────────────────────
echo ""
echo "4. Identity Center"
echo "────────────────────────────────────────────────────────"
IC_INSTANCE=$(aws sso-admin list-instances \
  --query 'Instances[0].InstanceArn' --output text 2>/dev/null || echo "NONE")
if [ "$IC_INSTANCE" != "NONE" ] && [ "$IC_INSTANCE" != "None" ] && [ -n "$IC_INSTANCE" ]; then
  pass "Identity Center enabled"
else
  info "Identity Center not found — not required for this lab but expected from Week 9"
fi

# ── Summary ────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
echo "  Pre-flight Summary"
echo "════════════════════════════════════════════════════════"
echo "  ✅ Passed:  $PASS"
echo "  ❌ Failed:  $FAIL"
echo "════════════════════════════════════════════════════════"
echo ""
if [ $FAIL -gt 0 ]; then
  echo "  Fix the items above before starting the lab."
else
  echo "  All checks passed — ready to start Week 12!"
fi
echo ""
