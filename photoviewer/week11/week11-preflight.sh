#!/bin/bash
# Week 11 Pre-flight Check — CS 55D
# Verifies the Week 10 environment is intact before starting Week 11.

# Note: no "set -e" — each check reports its own failure; the script must run to completion.
set -uo pipefail

PASS="\033[0;32m✓\033[0m"
FAIL="\033[0;31m✗\033[0m"
WARN="\033[0;33m⚠\033[0m"
errors=0

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Week 11 Pre-flight Check — CS 55D         ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# --- S3 bucket ---
echo "▸ Checking S3 bucket..."
BUCKET=$(aws s3api list-buckets --query "Buckets[?starts_with(Name,'photoviewer-')].Name" --output text 2>/dev/null | head -1)
if [ -n "$BUCKET" ]; then
    echo -e "  ${PASS} Photo Viewer bucket found: ${BUCKET}"
else
    echo -e "  ${FAIL} No S3 bucket starting with 'photoviewer-' found"
    errors=$((errors + 1))
fi

# --- photos/ prefix ---
if [ -n "$BUCKET" ]; then
    PHOTO_COUNT=$(aws s3 ls "s3://${BUCKET}/photos/" 2>/dev/null | wc -l)
    if [ "${PHOTO_COUNT:-0}" -gt 0 ]; then
        echo -e "  ${PASS} photos/ prefix exists (${PHOTO_COUNT} objects)"
    else
        echo -e "  ${WARN} photos/ prefix is empty — upload a test photo before starting"
    fi
fi

# --- CloudTrail ---
echo ""
echo "▸ Checking CloudTrail..."
TRAIL=$(aws cloudtrail describe-trails --query "trailList[0].Name" --output text 2>/dev/null)
if [ -n "$TRAIL" ] && [ "$TRAIL" != "None" ]; then
    echo -e "  ${PASS} CloudTrail trail found: ${TRAIL}"
else
    echo -e "  ${FAIL} No CloudTrail trail found"
    errors=$((errors + 1))
fi

# --- SNS topic ---
echo ""
echo "▸ Checking SNS topic..."
TOPIC=$(aws sns list-topics --query "Topics[0].TopicArn" --output text 2>/dev/null)
if [ -n "$TOPIC" ] && [ "$TOPIC" != "None" ]; then
    echo -e "  ${PASS} SNS topic found: $(echo $TOPIC | awk -F: '{print $NF}')"
    SUB_COUNT=$(aws sns list-subscriptions-by-topic --topic-arn "$TOPIC" --query "length(Subscriptions)" --output text 2>/dev/null)
    if [ "${SUB_COUNT:-0}" -gt 0 ]; then
        echo -e "  ${PASS} Topic has ${SUB_COUNT} subscription(s)"
    else
        echo -e "  ${WARN} Topic has no subscriptions — you may not receive email alerts"
    fi
else
    echo -e "  ${FAIL} No SNS topic found — create one and subscribe your email"
    errors=$((errors + 1))
fi

# --- Lambda function (from prior weeks) ---
echo ""
echo "▸ Checking Lambda functions..."
LAMBDA_COUNT=$(aws lambda list-functions --query "length(Functions)" --output text 2>/dev/null)
if [ "${LAMBDA_COUNT:-0}" -gt 0 ]; then
    echo -e "  ${PASS} ${LAMBDA_COUNT} Lambda function(s) found"
    aws lambda list-functions --query "Functions[].FunctionName" --output text 2>/dev/null | tr '\t' '\n' | while read fn; do
        echo "      · ${fn}"
    done
else
    echo -e "  ${WARN} No Lambda functions found — expected at least the API handler from prior weeks"
fi

# --- AWS Config recorder ---
echo ""
echo "▸ Checking AWS Config..."
CONFIG_STATUS=$(aws configservice describe-configuration-recorder-status --query "ConfigurationRecordersStatus[0].recording" --output text 2>/dev/null)
if [ "$CONFIG_STATUS" = "True" ]; then
    echo -e "  ${PASS} Config recorder is active"
else
    echo -e "  ${FAIL} Config recorder is not recording — enable it before starting"
    errors=$((errors + 1))
fi

# --- Week 10 Config rules (Security Hub ingests their findings in Step 14) ---
EXPECTED_RULES="s3-default-encryption-kms s3-bucket-public-read-prohibited cloud-trail-encryption-enabled iam-root-access-key-check"
EXISTING_RULES=$(aws configservice describe-config-rules --query "ConfigRules[].ConfigRuleName" --output text 2>/dev/null || true)
missing=0
for rule in $EXPECTED_RULES; do
    if echo "$EXISTING_RULES" | grep -qw "$rule"; then
        echo -e "  ${PASS} Config rule present: ${rule}"
    else
        echo -e "  ${FAIL} Config rule MISSING: ${rule} — Week 10 said keep all four rules through Week 11. Re-create it (Week 10 lab Step 7) or your Security Hub dashboard will have no Config findings."
        missing=$((missing + 1))
    fi
done
if [ "$missing" -gt 0 ]; then errors=$((errors + missing)); fi

# --- Inspector ---
echo ""
echo "▸ Checking Inspector..."
INSPECTOR_STATUS=$(aws inspector2 batch-get-account-status --query "accounts[0].state.status" --output text 2>/dev/null)
if [ "$INSPECTOR_STATUS" = "ENABLED" ]; then
    echo -e "  ${PASS} Inspector is enabled"
    # Check Lambda scanning
    LAMBDA_SCAN=$(aws inspector2 batch-get-account-status --query "accounts[0].resourceState.lambda.status" --output text 2>/dev/null)
    if [ "$LAMBDA_SCAN" = "ENABLED" ]; then
        echo -e "  ${PASS} Lambda scanning is enabled"
    else
        echo -e "  ${WARN} Lambda scanning may not be enabled — check Inspector settings"
    fi
else
    echo -e "  ${FAIL} Inspector is not enabled — enable it before starting"
    errors=$((errors + 1))
fi

# --- CloudWatch alarms ---
echo ""
echo "▸ Checking CloudWatch alarms..."
ALARM_COUNT=$(aws cloudwatch describe-alarms --query "length(MetricAlarms)" --output text 2>/dev/null)
if [ "${ALARM_COUNT:-0}" -gt 0 ]; then
    echo -e "  ${PASS} ${ALARM_COUNT} CloudWatch alarm(s) found"
else
    echo -e "  ${WARN} No CloudWatch alarms found — expected from Week 10"
fi

# --- Week 11 files ---
echo ""
echo "▸ Checking Week 11 lab files..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/image-validator.zip" ]; then
    ZIP_SIZE=$(ls -lh "${SCRIPT_DIR}/image-validator.zip" | awk '{print $5}')
    echo -e "  ${PASS} image-validator.zip found (${ZIP_SIZE})"
else
    echo -e "  ${FAIL} image-validator.zip not found in ${SCRIPT_DIR}"
    errors=$((errors + 1))
fi

if [ -f "${SCRIPT_DIR}/image_validator.py" ]; then
    echo -e "  ${PASS} image_validator.py source found"
else
    echo -e "  ${WARN} image_validator.py source not found (not required — it's inside the zip)"
fi

# --- Summary ---
echo ""
echo "─────────────────────────────────────────────"
if [ "$errors" -eq 0 ]; then
    echo -e "${PASS} All checks passed. Ready for Week 11."
else
    echo -e "${FAIL} ${errors} check(s) failed. Fix the issues above before starting."
fi
echo ""
