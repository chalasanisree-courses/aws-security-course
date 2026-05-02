#!/bin/bash
# Week 11 Post-flight Check — CS 55D
# Verifies that Week 11 lab resources have been properly cleaned up.

set -euo pipefail

PASS="\033[0;32m✓\033[0m"
FAIL="\033[0;31m✗\033[0m"
WARN="\033[0;33m⚠\033[0m"
issues=0

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Week 11 Post-flight Check — CS 55D        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# --- Macie ---
echo "▸ Checking Macie..."
MACIE_STATUS=$(aws macie2 get-macie-session --query "status" --output text 2>/dev/null || echo "DISABLED")
if [ "$MACIE_STATUS" = "ENABLED" ]; then
    echo -e "  ${FAIL} Macie is still enabled — disable it to avoid charges"
    echo "      Go to Macie → Settings → Disable Macie"
    issues=$((issues + 1))
else
    echo -e "  ${PASS} Macie is disabled"
fi

# --- GuardDuty ---
echo ""
echo "▸ Checking GuardDuty..."
GD_STATUS=$(aws guardduty list-detectors --query "DetectorIds" --output text 2>/dev/null)
if [ -n "$GD_STATUS" ] && [ "$GD_STATUS" != "None" ] && [ "$GD_STATUS" != "" ]; then
    DETECTOR_ID=$(echo "$GD_STATUS" | head -1)
    GD_ENABLED=$(aws guardduty get-detector --detector-id "$DETECTOR_ID" --query "Status" --output text 2>/dev/null || echo "UNKNOWN")
    if [ "$GD_ENABLED" = "ENABLED" ]; then
        echo -e "  ${FAIL} GuardDuty is still enabled — disable it to avoid charges"
        echo "      Go to GuardDuty → Settings → Suspend → Disable GuardDuty"
        issues=$((issues + 1))
    else
        echo -e "  ${PASS} GuardDuty is disabled"
    fi
else
    echo -e "  ${PASS} GuardDuty is disabled (no detector found)"
fi

# --- Security Hub ---
echo ""
echo "▸ Checking Security Hub..."
SH_STATUS=$(aws securityhub describe-hub --query "HubArn" --output text 2>/dev/null || echo "DISABLED")
if [ "$SH_STATUS" != "DISABLED" ] && [ -n "$SH_STATUS" ]; then
    echo -e "  ${FAIL} Security Hub is still enabled — disable it to avoid charges"
    echo "      Go to Security Hub → Settings → General → Disable Security Hub"
    issues=$((issues + 1))
else
    echo -e "  ${PASS} Security Hub is disabled"
fi

# --- EventBridge rules ---
echo ""
echo "▸ Checking EventBridge rules..."
EB_RULES=$(aws events list-rules --query "Rules[?starts_with(Name,'guardduty-')].Name" --output text 2>/dev/null)
if [ -n "$EB_RULES" ] && [ "$EB_RULES" != "None" ]; then
    echo -e "  ${FAIL} EventBridge rules still exist:"
    echo "$EB_RULES" | tr '\t' '\n' | while read rule; do
        echo "      · ${rule}"
    done
    echo "      Delete targets first, then delete the rules"
    issues=$((issues + 1))
else
    echo -e "  ${PASS} No guardduty-* EventBridge rules found"
fi

# --- Lambda functions ---
echo ""
echo "▸ Checking Lambda functions..."
VALIDATOR=$(aws lambda get-function --function-name photoviewer-image-validator --query "Configuration.FunctionName" --output text 2>/dev/null || echo "")
QUARANTINE=$(aws lambda get-function --function-name photoviewer-quarantine --query "Configuration.FunctionName" --output text 2>/dev/null || echo "")

if [ -n "$VALIDATOR" ]; then
    echo -e "  ${FAIL} photoviewer-image-validator still exists — delete it"
    issues=$((issues + 1))
else
    echo -e "  ${PASS} photoviewer-image-validator deleted"
fi

if [ -n "$QUARANTINE" ]; then
    echo -e "  ${FAIL} photoviewer-quarantine still exists — delete it"
    issues=$((issues + 1))
else
    echo -e "  ${PASS} photoviewer-quarantine deleted"
fi

# --- S3 event notification ---
echo ""
echo "▸ Checking S3 event notifications..."
BUCKET=$(aws s3api list-buckets --query "Buckets[?starts_with(Name,'photoviewer-')].Name" --output text 2>/dev/null | head -1)
if [ -n "$BUCKET" ]; then
    NOTIF_COUNT=$(aws s3api get-bucket-notification-configuration --bucket "$BUCKET" --query "length(LambdaFunctionConfigurations || \`[]\`)" --output text 2>/dev/null)
    if [ "$NOTIF_COUNT" -gt 0 ] 2>/dev/null; then
        echo -e "  ${FAIL} S3 event notification still configured on ${BUCKET}"
        echo "      Go to S3 → ${BUCKET} → Properties → Event notifications → Delete"
        issues=$((issues + 1))
    else
        echo -e "  ${PASS} No Lambda event notifications on ${BUCKET}"
    fi
else
    echo -e "  ${WARN} No photoviewer-* bucket found"
fi

# --- Test files ---
echo ""
echo "▸ Checking for leftover test files..."
if [ -n "$BUCKET" ]; then
    TEST_FILES=""
    for file in "photos/suspicious.jpg" "photos/test-photo.jpg" "photos/malware-test.jpg" "photos/customer-data.txt"; do
        if aws s3api head-object --bucket "$BUCKET" --key "$file" &>/dev/null; then
            TEST_FILES="${TEST_FILES}  ${file}\n"
        fi
    done
    # Check quarantine/ prefix
    QUARANTINE_COUNT=$(aws s3 ls "s3://${BUCKET}/quarantine/" 2>/dev/null | wc -l)

    if [ -n "$TEST_FILES" ] || [ "$QUARANTINE_COUNT" -gt 0 ]; then
        echo -e "  ${WARN} Leftover test files found:"
        if [ -n "$TEST_FILES" ]; then
            echo -e "$TEST_FILES" | while read f; do [ -n "$f" ] && echo "      · ${f}"; done
        fi
        if [ "$QUARANTINE_COUNT" -gt 0 ]; then
            echo "      · quarantine/ prefix has ${QUARANTINE_COUNT} object(s)"
        fi
    else
        echo -e "  ${PASS} No leftover test files found"
    fi
else
    echo -e "  ${WARN} Skipped — no bucket found"
fi

# --- Verify Week 10 services still running ---
echo ""
echo "▸ Verifying Week 10 services are still intact..."
CONFIG_STATUS=$(aws configservice describe-configuration-recorder-status --query "ConfigurationRecordersStatus[0].recording" --output text 2>/dev/null)
if [ "$CONFIG_STATUS" = "True" ]; then
    echo -e "  ${PASS} Config recorder still active"
else
    echo -e "  ${WARN} Config recorder not recording — re-enable if needed for Week 12"
fi

INSPECTOR_STATUS=$(aws inspector2 batch-get-account-status --query "accounts[0].state.status" --output text 2>/dev/null)
if [ "$INSPECTOR_STATUS" = "ENABLED" ]; then
    echo -e "  ${PASS} Inspector still enabled"
else
    echo -e "  ${WARN} Inspector not enabled — re-enable if needed"
fi

TRAIL=$(aws cloudtrail describe-trails --query "trailList[0].Name" --output text 2>/dev/null)
if [ -n "$TRAIL" ] && [ "$TRAIL" != "None" ]; then
    LOGGING=$(aws cloudtrail get-trail-status --name "$TRAIL" --query "IsLogging" --output text 2>/dev/null)
    if [ "$LOGGING" = "True" ]; then
        echo -e "  ${PASS} CloudTrail logging active"
    else
        echo -e "  ${FAIL} CloudTrail logging is stopped — re-enable immediately"
        echo "      Go to CloudTrail → Trails → ${TRAIL} → Start logging"
        issues=$((issues + 1))
    fi
else
    echo -e "  ${WARN} No CloudTrail trail found"
fi

# --- Summary ---
echo ""
echo "─────────────────────────────────────────────"
if [ "$issues" -eq 0 ]; then
    echo -e "${PASS} Cleanup complete. Ready for Week 12."
else
    echo -e "${FAIL} ${issues} item(s) still need attention. Fix the issues above."
fi
echo ""
