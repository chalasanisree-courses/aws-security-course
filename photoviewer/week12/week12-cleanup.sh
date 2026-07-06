#!/bin/bash
# ============================================================
# CS 55D — End-of-Course Cleanup
# Removes all AWS resources created across Weeks 1–12.
#
# Run from CloudShell:
#   bash aws-security-course/photoviewer/week12/week12-cleanup.sh
#
# ⚠️  This script DELETES resources. Review each section.
#     Some resources require manual action (noted below).
# ============================================================

set +e
REGION="us-east-1"
DELETED=0; SKIPPED=0; MANUAL=0

# Detection services (Security Hub, GuardDuty, Macie, Inspector, Config) are REGIONAL.
# Students frequently end up with them enabled in more than one region, and disabling
# only us-east-1 is the #1 cause of lingering charges after the course. We handle the
# primary region in full below, then sweep every other region (Section 2b).
ALL_REGIONS=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null || echo "$REGION")
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "")

deleted() { echo "  ✅ Deleted: $1"; ((DELETED++)); }
skipped() { echo "  ⏭️  Skipped: $1"; ((SKIPPED++)); }
manual()  { echo "  🔧 Manual action needed: $1"; ((MANUAL++)); }
info()    { echo "  ℹ️  $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  CS 55D — End-of-Course Cleanup                      ║"
echo "║  This will remove all PhotoViewer resources.          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
read -p "Are you sure you want to clean up all course resources? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi
echo ""


# ════════════════════════════════════════════════════════════
echo "1. WEEK 12 — SCPs and Organizations policies"
echo "────────────────────────────────────────────────────────"

# Detach and delete SCPs
SCP_NAMES=("deny-cloudtrail-disable" "deny-public-s3" "restrict-region-us-east-1" "deny-identity-center-admin")
for SCP_NAME in "${SCP_NAMES[@]}"; do
  SCP_ID=$(aws organizations list-policies --filter SERVICE_CONTROL_POLICY --query "Policies[?Name=='$SCP_NAME'].Id" --output text 2>/dev/null || echo "")
  if [ -n "$SCP_ID" ] && [ "$SCP_ID" != "None" ]; then
    # Detach from all targets
    TARGETS=$(aws organizations list-targets-for-policy --policy-id "$SCP_ID" --query 'Targets[].TargetId' --output text 2>/dev/null || echo "")
    for TARGET in $TARGETS; do
      aws organizations detach-policy --policy-id "$SCP_ID" --target-id "$TARGET" 2>/dev/null || true
    done
    aws organizations delete-policy --policy-id "$SCP_ID" 2>/dev/null && deleted "SCP: $SCP_NAME" || skipped "SCP: $SCP_NAME (could not delete)"
  else
    skipped "SCP: $SCP_NAME (not found)"
  fi
done


# ════════════════════════════════════════════════════════════
echo ""
echo "2. WEEK 11 — Detection and Response resources"
echo "────────────────────────────────────────────────────────"

# EventBridge rules
for RULE_NAME in "guardduty-high-severity-alert" "guardduty-malware-quarantine"; do
  if aws events describe-rule --name "$RULE_NAME" --region "$REGION" &>/dev/null; then
    # Remove targets first
    TARGET_IDS=$(aws events list-targets-by-rule --rule "$RULE_NAME" --region "$REGION" --query 'Targets[].Id' --output text 2>/dev/null || echo "")
    if [ -n "$TARGET_IDS" ]; then
      aws events remove-targets --rule "$RULE_NAME" --ids $TARGET_IDS --region "$REGION" 2>/dev/null || true
    fi
    aws events delete-rule --name "$RULE_NAME" --region "$REGION" 2>/dev/null && deleted "EventBridge rule: $RULE_NAME" || skipped "EventBridge rule: $RULE_NAME"
  else
    skipped "EventBridge rule: $RULE_NAME (not found)"
  fi
done

# Quarantine Lambda
if aws lambda get-function --function-name "photoviewer-quarantine" --region "$REGION" &>/dev/null; then
  aws lambda delete-function --function-name "photoviewer-quarantine" --region "$REGION" 2>/dev/null && deleted "Lambda: photoviewer-quarantine" || skipped "Lambda: photoviewer-quarantine"
else
  skipped "Lambda: photoviewer-quarantine (not found)"
fi

# Image validator Lambda
if aws lambda get-function --function-name "photoviewer-image-validator" --region "$REGION" &>/dev/null; then
  aws lambda delete-function --function-name "photoviewer-image-validator" --region "$REGION" 2>/dev/null && deleted "Lambda: photoviewer-image-validator" || skipped "Lambda: photoviewer-image-validator"
  # The bucket's event notification still points at this (now deleted) Lambda — remove it
  NOTIF_BUCKET=$(aws s3api list-buckets --query "Buckets[?starts_with(Name,'photoviewer-')].Name" --output text 2>/dev/null | head -1)
  if [ -n "$NOTIF_BUCKET" ]; then
    aws s3api put-bucket-notification-configuration --bucket "$NOTIF_BUCKET" --notification-configuration '{}' --region "$REGION" 2>/dev/null       && deleted "S3 event notification on $NOTIF_BUCKET (was pointing at deleted validator Lambda)"       || skipped "S3 event notification (could not clear)"
  fi
else
  skipped "Lambda: photoviewer-image-validator (not found)"
fi

# Security Hub
SH_STATUS=$(aws securityhub describe-hub --region "$REGION" --query 'HubArn' --output text 2>/dev/null || echo "NONE")
if [ "$SH_STATUS" != "NONE" ]; then
  # Deregister as delegated admin first (required if account is the org admin for Security Hub)
  ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "")
  if [ -n "$ACCOUNT_ID" ]; then
    aws securityhub disable-organization-admin-account --admin-account-id "$ACCOUNT_ID" --region "$REGION" 2>/dev/null || true
  fi
  aws organizations disable-aws-service-access --service-principal securityhub.amazonaws.com 2>/dev/null || true
  # Delete the cross-region finding aggregator if one exists (links regions together)
  AGG_ARN=$(aws securityhub list-finding-aggregators --region "$REGION" --query 'FindingAggregators[0].FindingAggregatorArn' --output text 2>/dev/null || echo "None")
  if [ -n "$AGG_ARN" ] && [ "$AGG_ARN" != "None" ]; then
    aws securityhub delete-finding-aggregator --finding-aggregator-arn "$AGG_ARN" --region "$REGION" 2>/dev/null && info "Deleted Security Hub finding aggregator" || true
  fi
  aws securityhub disable-security-hub --region "$REGION" 2>/dev/null && deleted "Security Hub" || skipped "Security Hub (could not disable)"
  # Security Hub creates securityhub-* Config rules — it can take 10+ minutes to remove them.
  # Poll until they are gone (or give up after ~10 minutes), then force-delete any leftovers.
  info "Waiting for Security Hub to clean up its Config rules (can take 10+ minutes)..."
  for attempt in $(seq 1 20); do
    SH_REMAINING=$(aws configservice describe-config-rules --region "$REGION"       --query "length(ConfigRules[?starts_with(ConfigRuleName,'securityhub-')])"       --output text 2>/dev/null || echo 0)
    case "$SH_REMAINING" in (*[!0-9]*|"") SH_REMAINING=0 ;; esac
    if [ "$SH_REMAINING" -eq 0 ]; then break; fi
    info "  ...${SH_REMAINING} securityhub-* rule(s) remain (check ${attempt}/20), waiting 30s"
    sleep 30
  done
  SH_RULES=$(aws configservice describe-config-rules --region "$REGION" \
    --query "ConfigRules[?starts_with(ConfigRuleName,'securityhub-')].ConfigRuleName" \
    --output text 2>/dev/null || echo "")
  if [ -n "$SH_RULES" ] && [ "$SH_RULES" != "None" ]; then
    for SH_RULE in $SH_RULES; do
      aws configservice delete-config-rule --config-rule-name "$SH_RULE" --region "$REGION" 2>/dev/null && deleted "Config rule (Security Hub leftover): $SH_RULE" || skipped "Config rule: $SH_RULE (may still be cleaning up)"
    done
  fi
else
  skipped "Security Hub (not enabled)"
fi

# GuardDuty
GD_DETECTOR=$(aws guardduty list-detectors --region "$REGION" --query 'DetectorIds[0]' --output text 2>/dev/null || echo "NONE")
if [ "$GD_DETECTOR" != "NONE" ] && [ "$GD_DETECTOR" != "None" ]; then
  aws guardduty delete-detector --detector-id "$GD_DETECTOR" --region "$REGION" 2>/dev/null && deleted "GuardDuty detector: $GD_DETECTOR" || skipped "GuardDuty"
else
  skipped "GuardDuty (not enabled)"
fi

# Macie
MACIE_STATUS=$(aws macie2 get-macie-session --region "$REGION" --query 'status' --output text 2>/dev/null || echo "NONE")
if [ "$MACIE_STATUS" = "ENABLED" ]; then
  aws macie2 disable-macie --region "$REGION" 2>/dev/null && deleted "Macie" || skipped "Macie (could not disable)"
else
  skipped "Macie (not enabled or already disabled)"
fi


# ════════════════════════════════════════════════════════════
echo ""
echo "2b. MULTI-REGION SWEEP — detection services in OTHER regions"
echo "────────────────────────────────────────────────────────"
echo "   Security Hub, GuardDuty, Macie, and Inspector are regional. Disabling only"
echo "   us-east-1 leaves the rest billing — this sweep catches them everywhere else."

for R in $ALL_REGIONS; do
  [ "$R" = "$REGION" ] && continue   # primary region handled above / in Section 3

  # ── Security Hub (deregister org admin + finding aggregator, then disable) ──
  if aws securityhub describe-hub --region "$R" >/dev/null 2>&1; then
    [ -n "$ACCOUNT_ID" ] && aws securityhub disable-organization-admin-account --admin-account-id "$ACCOUNT_ID" --region "$R" 2>/dev/null || true
    AGG_R=$(aws securityhub list-finding-aggregators --region "$R" --query 'FindingAggregators[0].FindingAggregatorArn' --output text 2>/dev/null || echo "None")
    [ -n "$AGG_R" ] && [ "$AGG_R" != "None" ] && aws securityhub delete-finding-aggregator --finding-aggregator-arn "$AGG_R" --region "$R" 2>/dev/null || true
    aws securityhub disable-security-hub --region "$R" 2>/dev/null && deleted "Security Hub ($R)" || skipped "Security Hub ($R — check delegated admin)"
  fi

  # ── securityhub-* Config rules left behind in this region ──
  for SH_RULE in $(aws configservice describe-config-rules --region "$R" --query "ConfigRules[?starts_with(ConfigRuleName,'securityhub-')].ConfigRuleName" --output text 2>/dev/null || echo ""); do
    [ -n "$SH_RULE" ] && aws configservice delete-config-rule --config-rule-name "$SH_RULE" --region "$R" 2>/dev/null && deleted "securityhub-* Config rule ($R): $SH_RULE"
  done

  # ── GuardDuty ──
  GD_R=$(aws guardduty list-detectors --region "$R" --query 'DetectorIds[0]' --output text 2>/dev/null || echo "None")
  if [ -n "$GD_R" ] && [ "$GD_R" != "None" ] && [ "$GD_R" != "NONE" ]; then
    aws guardduty delete-detector --detector-id "$GD_R" --region "$R" 2>/dev/null && deleted "GuardDuty ($R)" || skipped "GuardDuty ($R)"
  fi

  # ── Macie ──
  if [ "$(aws macie2 get-macie-session --region "$R" --query 'status' --output text 2>/dev/null || echo NONE)" = "ENABLED" ]; then
    aws macie2 disable-macie --region "$R" 2>/dev/null && deleted "Macie ($R)" || skipped "Macie ($R)"
  fi

  # ── Inspector ──
  if [ "$(aws inspector2 batch-get-account-status --region "$R" --query 'accounts[0].state.status' --output text 2>/dev/null || echo NONE)" = "ENABLED" ]; then
    aws inspector2 disable --resource-types LAMBDA EC2 ECR --region "$R" 2>/dev/null && deleted "Inspector ($R)" || skipped "Inspector ($R)"
  fi
done


# ════════════════════════════════════════════════════════════
echo ""
echo "3. WEEK 10 — Monitoring resources"
echo "────────────────────────────────────────────────────────"

# CloudWatch alarms
for ALARM in $(aws cloudwatch describe-alarms --region "$REGION" --query "MetricAlarms[?contains(AlarmName,'photoviewer')].AlarmName" --output text 2>/dev/null || echo ""); do
  if [ -n "$ALARM" ]; then
    aws cloudwatch delete-alarms --alarm-names "$ALARM" --region "$REGION" 2>/dev/null && deleted "CloudWatch alarm: $ALARM" || skipped "Alarm: $ALARM"
  fi
done

# AWS Config rules
for RULE in $(aws configservice describe-config-rules --region "$REGION" --query 'ConfigRules[].ConfigRuleName' --output text 2>/dev/null || echo ""); do
  if [ -n "$RULE" ]; then
    aws configservice delete-config-rule --config-rule-name "$RULE" --region "$REGION" 2>/dev/null && deleted "Config rule: $RULE" || skipped "Config rule: $RULE"
  fi
done

# AWS Config recorder
RECORDER=$(aws configservice describe-configuration-recorders --region "$REGION" --query 'ConfigurationRecorders[0].name' --output text 2>/dev/null || echo "NONE")
if [ "$RECORDER" != "NONE" ] && [ "$RECORDER" != "None" ]; then
  aws configservice stop-configuration-recorder --configuration-recorder-name "$RECORDER" --region "$REGION" 2>/dev/null || true
  aws configservice delete-configuration-recorder --configuration-recorder-name "$RECORDER" --region "$REGION" 2>/dev/null && deleted "Config recorder: $RECORDER" || skipped "Config recorder"
  # Delete delivery channel
  CHANNEL=$(aws configservice describe-delivery-channels --region "$REGION" --query 'DeliveryChannels[0].name' --output text 2>/dev/null || echo "NONE")
  if [ "$CHANNEL" != "NONE" ] && [ "$CHANNEL" != "None" ]; then
    aws configservice delete-delivery-channel --delivery-channel-name "$CHANNEL" --region "$REGION" 2>/dev/null && deleted "Config delivery channel" || skipped "Config delivery channel"
  fi
else
  skipped "Config recorder (not found)"
fi

# Inspector
INSPECTOR_STATUS=$(aws inspector2 batch-get-account-status --region "$REGION" --query 'accounts[0].state.status' --output text 2>/dev/null || echo "NONE")
if [ "$INSPECTOR_STATUS" = "ENABLED" ]; then
  aws inspector2 disable --resource-types LAMBDA --region "$REGION" 2>/dev/null && deleted "Inspector Lambda scanning" || skipped "Inspector"
else
  skipped "Inspector (not enabled)"
fi


# ════════════════════════════════════════════════════════════
echo ""
echo "4. WEEKS 5–9 — Application resources"
echo "────────────────────────────────────────────────────────"

# Main Lambda function
if aws lambda get-function --function-name "photoviewer-lambda" --region "$REGION" &>/dev/null; then
  aws lambda delete-function --function-name "photoviewer-lambda" --region "$REGION" 2>/dev/null && deleted "Lambda: photoviewer-lambda" || skipped "Lambda: photoviewer-lambda"
else
  skipped "Lambda: photoviewer-lambda (not found)"
fi

# API Gateway — list and flag
API_IDS=$(aws apigatewayv2 get-apis --region "$REGION" --query "Items[?contains(Name,'photoviewer') || contains(Name,'PhotoViewer')].ApiId" --output text 2>/dev/null || echo "")
if [ -n "$API_IDS" ]; then
  for API_ID in $API_IDS; do
    aws apigatewayv2 delete-api --api-id "$API_ID" --region "$REGION" 2>/dev/null && deleted "API Gateway: $API_ID" || skipped "API Gateway: $API_ID"
  done
else
  # Check REST APIs too
  REST_IDS=$(aws apigateway get-rest-apis --region "$REGION" --query "items[?contains(name,'photoviewer') || contains(name,'PhotoViewer')].id" --output text 2>/dev/null || echo "")
  if [ -n "$REST_IDS" ]; then
    for REST_ID in $REST_IDS; do
      aws apigateway delete-rest-api --rest-api-id "$REST_ID" --region "$REGION" 2>/dev/null && deleted "REST API: $REST_ID" || skipped "REST API: $REST_ID"
    done
  else
    skipped "API Gateway (not found)"
  fi
fi

# DynamoDB table
if aws dynamodb describe-table --table-name "photoviewer-photos" --region "$REGION" &>/dev/null; then
  aws dynamodb delete-table --table-name "photoviewer-photos" --region "$REGION" 2>/dev/null && deleted "DynamoDB: photoviewer-photos" || skipped "DynamoDB table"
else
  skipped "DynamoDB: photoviewer-photos (not found)"
fi

# Cognito user pool
POOL_ID=$(aws cognito-idp list-user-pools --max-results 10 --region "$REGION" --query "UserPools[?contains(Name,'photoviewer') || contains(Name,'PhotoViewer')].Id" --output text 2>/dev/null || echo "")
if [ -n "$POOL_ID" ] && [ "$POOL_ID" != "None" ]; then
  # Must delete domain first
  DOMAIN=$(aws cognito-idp describe-user-pool --user-pool-id "$POOL_ID" --region "$REGION" --query 'UserPool.Domain' --output text 2>/dev/null || echo "")
  if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "None" ]; then
    aws cognito-idp delete-user-pool-domain --user-pool-id "$POOL_ID" --domain "$DOMAIN" --region "$REGION" 2>/dev/null || true
  fi
  aws cognito-idp delete-user-pool --user-pool-id "$POOL_ID" --region "$REGION" 2>/dev/null && deleted "Cognito user pool: $POOL_ID" || skipped "Cognito user pool"
else
  skipped "Cognito user pool (not found)"
fi

# Secrets Manager
for SECRET in $(aws secretsmanager list-secrets --region "$REGION" --query "SecretList[?contains(Name,'photoviewer')].Name" --output text 2>/dev/null || echo ""); do
  if [ -n "$SECRET" ]; then
    aws secretsmanager delete-secret --secret-id "$SECRET" --force-delete-without-recovery --region "$REGION" 2>/dev/null && deleted "Secret: $SECRET" || skipped "Secret: $SECRET"
  fi
done

# SNS topics (only photoviewer/security-related, not billing alarms)
for TOPIC in $(aws sns list-topics --region "$REGION" --query "Topics[].TopicArn" --output text 2>/dev/null || echo ""); do
  TOPIC_NAME=$(echo "$TOPIC" | awk -F: '{print $NF}')
  if echo "$TOPIC_NAME" | grep -qi "photoviewer\|guardduty\|security-alert"; then
    aws sns delete-topic --topic-arn "$TOPIC" --region "$REGION" 2>/dev/null && deleted "SNS topic: $TOPIC_NAME" || skipped "SNS topic: $TOPIC_NAME"
  fi
done


# ════════════════════════════════════════════════════════════
echo ""
echo "5. WEEKS 2–4 — Network and distribution resources"
echo "────────────────────────────────────────────────────────"

# CloudFront — requires manual disable + delete (can take 15+ min)
CF_DIST=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Comment,'photoviewer') || contains(Comment,'PhotoViewer')].Id" --output text 2>/dev/null || echo "")
if [ -n "$CF_DIST" ] && [ "$CF_DIST" != "None" ]; then
  manual "CloudFront distribution: $CF_DIST — disable in console, wait for deployment, then delete"
else
  CF_DIST=$(aws cloudfront list-distributions --query "DistributionList.Items[0].Id" --output text 2>/dev/null || echo "")
  if [ -n "$CF_DIST" ] && [ "$CF_DIST" != "None" ]; then
    manual "CloudFront distribution found: $CF_DIST — verify it is the PhotoViewer distribution, then disable and delete in console"
  else
    skipped "CloudFront distribution (not found)"
  fi
fi

# WAF Web ACL — bundled (free, auto-removed with the distribution) vs custom standalone (~$5/mo)
WAF_ACLS=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query "WebACLs[].Name" --output text 2>/dev/null || echo "")
if [ -n "$WAF_ACLS" ] && [ "$WAF_ACLS" != "None" ]; then
  for acl in $WAF_ACLS; do
    case "$acl" in
      CreatedByCloudFront-*)
        skipped "WAF Web ACL $acl — bundled with the CloudFront Free plan (\$0); removed automatically when you delete the distribution, no action needed" ;;
      *)
        manual "WAF Web ACL $acl — custom standalone (~\$5/month): disassociate from CloudFront, then delete in console" ;;
    esac
  done
else
  skipped "WAF Web ACL (not found)"
fi

# VPC — flag for manual cleanup (subnets, security groups, route tables, IGW)
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Name,Values=*photoviewer*,*PhotoViewer*" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")
if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
  manual "VPC: $VPC_ID — delete subnets, security groups, route tables, internet gateway, then the VPC in console"
else
  info "No PhotoViewer-tagged VPC found (may have been cleaned up in a prior week or uses default naming)"
fi


# ════════════════════════════════════════════════════════════
echo ""
echo "6. WEEK 8 — KMS keys"
echo "────────────────────────────────────────────────────────"

for KEY_ALIAS in "alias/photoviewer-data-key" "alias/photoviewer-infra-key"; do
  KEY_ID=$(aws kms describe-key --key-id "$KEY_ALIAS" --region "$REGION" --query 'KeyMetadata.KeyId' --output text 2>/dev/null || echo "NONE")
  if [ "$KEY_ID" != "NONE" ]; then
    KEY_STATE=$(aws kms describe-key --key-id "$KEY_ID" --region "$REGION" --query 'KeyMetadata.KeyState' --output text 2>/dev/null || echo "")
    if [ "$KEY_STATE" = "Enabled" ]; then
      aws kms schedule-key-deletion --key-id "$KEY_ID" --pending-window-in-days 7 --region "$REGION" 2>/dev/null && deleted "KMS key scheduled for deletion (7 days): $KEY_ALIAS" || skipped "KMS key: $KEY_ALIAS"
    elif [ "$KEY_STATE" = "PendingDeletion" ]; then
      info "KMS key already pending deletion: $KEY_ALIAS"
    else
      skipped "KMS key in state $KEY_STATE: $KEY_ALIAS"
    fi
  else
    skipped "KMS key: $KEY_ALIAS (not found)"
  fi
done


# ════════════════════════════════════════════════════════════
echo ""
echo "7. S3 BUCKET"
echo "────────────────────────────────────────────────────────"

BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'photoviewer')].Name" --output text 2>/dev/null || echo "")
if [ -n "$BUCKET" ]; then
  manual "S3 bucket: $BUCKET — empty the bucket first (delete all objects including quarantine/), then delete the bucket in console"
else
  skipped "PhotoViewer S3 bucket (not found)"
fi

# Config bucket (created by AWS Config)
CONFIG_BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'config-bucket')].Name" --output text 2>/dev/null || echo "")
if [ -n "$CONFIG_BUCKET" ]; then
  manual "S3 bucket: $CONFIG_BUCKET — created by AWS Config. Empty and delete in console if Config is disabled."
else
  skipped "Config S3 bucket (not found)"
fi


# ════════════════════════════════════════════════════════════
echo ""
echo "8. IDENTITY CENTER and ORGANIZATIONS"
echo "────────────────────────────────────────────────────────"

manual "Identity Center — delete permission sets (Tom, Jerry), then delete users in the Identity Center console"
manual "Organizations — remove account from Production OU, then consider whether to delete the organization (this disables Identity Center and SCPs)"
info "If you plan to reuse this account, you may want to keep Organizations and Identity Center."


# ════════════════════════════════════════════════════════════
echo ""
echo "9. IAM ROLES and POLICIES"
echo "────────────────────────────────────────────────────────"

# List photoviewer-related roles
ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName,'photoviewer') || contains(RoleName,'PhotoViewer')].RoleName" --output text 2>/dev/null || echo "")
if [ -n "$ROLES" ]; then
  for ROLE in $ROLES; do
    manual "IAM role: $ROLE — detach policies, remove from instance profiles, then delete"
  done
else
  info "No PhotoViewer-specific IAM roles found (Lambda execution roles may use generic names)"
fi

# Flag Lambda execution roles
LAMBDA_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName,'lambda') || contains(RoleName,'Lambda')].RoleName" --output text 2>/dev/null || echo "")
if [ -n "$LAMBDA_ROLES" ]; then
  info "Lambda execution roles found (review and delete if no longer needed):"
  for R in $LAMBDA_ROLES; do
    echo "      $R"
  done
fi

# EventBridge invoke Lambda roles (auto-created by EventBridge)
EB_ROLES=$(aws iam list-roles --query "Roles[?starts_with(RoleName,'Amazon_EventBridge_Invoke_Lambda')].RoleName" --output text 2>/dev/null || echo "")
if [ -n "$EB_ROLES" ]; then
  for EB_ROLE in $EB_ROLES; do
    # Detach all policies first
    for POLICY_ARN in $(aws iam list-attached-role-policies --role-name "$EB_ROLE" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo ""); do
      aws iam detach-role-policy --role-name "$EB_ROLE" --policy-arn "$POLICY_ARN" 2>/dev/null || true
    done
    for POLICY_NAME in $(aws iam list-role-policies --role-name "$EB_ROLE" --query 'PolicyNames[]' --output text 2>/dev/null || echo ""); do
      aws iam delete-role-policy --role-name "$EB_ROLE" --policy-name "$POLICY_NAME" 2>/dev/null || true
    done
    aws iam delete-role --role-name "$EB_ROLE" 2>/dev/null && deleted "IAM role: $EB_ROLE" || skipped "IAM role: $EB_ROLE"
  done
fi


# ════════════════════════════════════════════════════════════
echo ""
echo "10. CLOUDTRAIL"
echo "────────────────────────────────────────────────────────"

TRAIL_NAME=$(aws cloudtrail describe-trails --region "$REGION" --query 'trailList[0].Name' --output text 2>/dev/null || echo "NONE")
if [ "$TRAIL_NAME" != "NONE" ] && [ "$TRAIL_NAME" != "None" ]; then
  manual "CloudTrail trail: $TRAIL_NAME — delete in console if no longer needed. Also delete the CloudTrail S3 bucket if it was auto-created."
else
  skipped "CloudTrail (not found)"
fi


# ════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════════════"
echo "  Cleanup Summary"
echo "════════════════════════════════════════════════════════"
echo "  ✅ Deleted automatically:    $DELETED"
echo "  ⏭️  Skipped (not found):      $SKIPPED"
echo "  🔧 Manual action required:   $MANUAL"
echo "════════════════════════════════════════════════════════"
echo ""
if [ $MANUAL -gt 0 ]; then
  echo "  Items marked 🔧 require manual cleanup in the AWS console."
  echo "  These resources either have dependencies that must be removed"
  echo "  first, or require confirmation before deletion."
fi
echo ""
echo "  After completing manual cleanup, verify with:"
echo "    aws ce get-cost-and-usage --time-period Start=$(date -d '-1 day' +%Y-%m-%d),End=$(date +%Y-%m-%d) --granularity DAILY --metrics BlendedCost"
echo ""
echo "  Thank you for taking CS 55D! 🎓"
echo ""
