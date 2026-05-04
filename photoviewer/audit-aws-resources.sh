#!/bin/bash
# =============================================================
# CS 55D — AWS Resource Audit Script
# Run this in AWS CloudShell (us-east-1) to see what you have
# running and what is costing you money.
#
# Usage:
#   bash audit-aws-resources.sh
# =============================================================

REGION="us-east-1"
echo ""
echo "=============================================="
echo " CS 55D — AWS Resource Audit  (region: $REGION)"
echo "=============================================="

# ── EC2 Instances ──────────────────────────────────────────
echo ""
echo "[ EC2 Instances ]"
echo "  running/stopped = may cost money"
echo "  terminated      = safe, will disappear soon"
aws ec2 describe-instances \
  --region $REGION \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# ── ALB / NLB ──────────────────────────────────────────────
echo ""
echo "[ Load Balancers ] (~\$16/month each minimum)"
aws elbv2 describe-load-balancers \
  --region $REGION \
  --query 'LoadBalancers[].[LoadBalancerName,State.Code,Type]' \
  --output table

# ── Target Groups ──────────────────────────────────────────
echo ""
echo "[ Target Groups ] (free, but clean up orphans)"
aws elbv2 describe-target-groups \
  --region $REGION \
  --query 'TargetGroups[].[TargetGroupName,TargetGroupArn]' \
  --output table

# ── NAT Gateways ───────────────────────────────────────────
echo ""
echo "[ NAT Gateways ] (~\$32/month — delete when not needed)"
aws ec2 describe-nat-gateways \
  --region $REGION \
  --filter Name=state,Values=available,pending \
  --query 'NatGateways[].[NatGatewayId,State,VpcId]' \
  --output table

# ── Elastic IPs ────────────────────────────────────────────
echo ""
echo "[ Elastic IPs ] (~\$4/month if unattached)"
aws ec2 describe-addresses \
  --region $REGION \
  --query 'Addresses[].[PublicIp,AllocationId,AssociationId]' \
  --output table

# ── VPC Endpoints ──────────────────────────────────────────
echo ""
echo "[ VPC Interface Endpoints ] (~\$7/month each)"
echo "  Gateway endpoints (S3, DynamoDB) are FREE"
aws ec2 describe-vpc-endpoints \
  --region $REGION \
  --query 'VpcEndpoints[?State==`available`].[VpcEndpointId,VpcEndpointType,ServiceName]' \
  --output table

# ── VPCs ───────────────────────────────────────────────────
echo ""
echo "[ VPCs ] (free — but shows what you have)"
aws ec2 describe-vpcs \
  --region $REGION \
  --query 'Vpcs[].[VpcId,State,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# ── RDS ────────────────────────────────────────────────────
echo ""
echo "[ RDS Instances ] (can be expensive — check carefully)"
aws rds describe-db-instances \
  --region $REGION \
  --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,DBInstanceClass]' \
  --output table 2>/dev/null || echo "  (none)"

# ── DynamoDB ───────────────────────────────────────────────
echo ""
echo "[ DynamoDB Tables ] (free tier covers course usage)"
aws dynamodb list-tables \
  --region $REGION \
  --output table

# ── S3 Buckets ─────────────────────────────────────────────
echo ""
echo "[ S3 Buckets ] (free tier covers course usage)"
aws s3 ls

# ── CloudFront ─────────────────────────────────────────────
echo ""
echo "[ CloudFront Distributions ] (free tier covers course usage)"
aws cloudfront list-distributions \
  --query 'DistributionList.Items[].[Id,DomainName,Status]' \
  --output table 2>/dev/null || echo "  (none)"

# ── WAF Web ACLs ───────────────────────────────────────────
echo ""
echo "[ WAF Web ACLs ]"
echo "  CreatedByCloudFront-* = managed by CloudFront Security dashboard (FREE)"
echo "  Custom Web ACLs       = ~\$5/month each"
aws wafv2 list-web-acls \
  --scope CLOUDFRONT \
  --region us-east-1 \
  --query 'WebACLs[].[Name,Id]' \
  --output table 2>/dev/null || echo "  (none)"

# ── Lambda Functions ───────────────────────────────────────
echo ""
echo "[ Lambda Functions ] (free tier covers course usage)"
aws lambda list-functions \
  --region $REGION \
  --query 'Functions[].[FunctionName,Runtime,LastModified]' \
  --output table 2>/dev/null || echo "  (none)"

# ── API Gateway HTTP APIs ──────────────────────────────────
echo ""
echo "[ API Gateway HTTP APIs ] (free tier covers course usage)"
aws apigatewayv2 list-apis \
  --region $REGION \
  --query 'Items[].[Name,ApiId,ProtocolType]' \
  --output table 2>/dev/null || echo "  (none)"

# ── CloudTrail ─────────────────────────────────────────────
echo ""
echo "[ CloudTrail Trails ]"
aws cloudtrail describe-trails \
  --region $REGION \
  --query 'trailList[].[Name,S3BucketName,IsLogging]' \
  --output table 2>/dev/null || echo "  (none)"

# ── CloudWatch Alarms ─────────────────────────────────────
echo ""
echo "[ CloudWatch Alarms ] (free tier covers 10 alarms)"
aws cloudwatch describe-alarms \
  --region $REGION \
  --query 'MetricAlarms[].[AlarmName,StateValue,MetricName]' \
  --output table 2>/dev/null || echo "  (none)"

# ── AWS Config ────────────────────────────────────────────
echo ""
echo "[ AWS Config ] (~\$1-2/month — recorder + rules)"
RECORDER_STATUS=$(aws configservice describe-configuration-recorder-status \
  --region $REGION \
  --query 'ConfigurationRecordersStatus[0].recording' \
  --output text 2>/dev/null || echo "NONE")
echo "  Recorder active: $RECORDER_STATUS"
aws configservice describe-config-rules \
  --region $REGION \
  --query 'ConfigRules[].[ConfigRuleName,ConfigRuleState]' \
  --output table 2>/dev/null || echo "  No Config rules"

# ── Inspector ─────────────────────────────────────────────
echo ""
echo "[ Inspector ] (free 15-day trial, then ~\$0.15/Lambda rescan)"
INSPECTOR_STATUS=$(aws inspector2 batch-get-account-status \
  --region $REGION \
  --query 'accounts[0].state.status' \
  --output text 2>/dev/null || echo "NONE")
echo "  Status: $INSPECTOR_STATUS"

# ── GuardDuty ─────────────────────────────────────────────
echo ""
echo "[ GuardDuty ] (free 30-day trial, then pay per event volume)"
GD_DETECTOR=$(aws guardduty list-detectors \
  --region $REGION \
  --query 'DetectorIds[0]' \
  --output text 2>/dev/null || echo "NONE")
if [ "$GD_DETECTOR" != "NONE" ] && [ "$GD_DETECTOR" != "None" ] && [ -n "$GD_DETECTOR" ]; then
  echo "  Detector: $GD_DETECTOR (ACTIVE)"
else
  echo "  Not enabled"
fi

# ── Security Hub ──────────────────────────────────────────
echo ""
echo "[ Security Hub ] (free 30-day trial, then per finding)"
SH_ARN=$(aws securityhub describe-hub \
  --region $REGION \
  --query 'HubArn' \
  --output text 2>/dev/null || echo "NONE")
if [ "$SH_ARN" != "NONE" ]; then
  echo "  Enabled: $SH_ARN"
else
  echo "  Not enabled"
fi

# ── Macie ─────────────────────────────────────────────────
echo ""
echo "[ Macie ] (free 30-day trial, then per GB scanned)"
MACIE_STATUS=$(aws macie2 get-macie-session \
  --region $REGION \
  --query 'status' \
  --output text 2>/dev/null || echo "NONE")
echo "  Status: $MACIE_STATUS"

# ── EventBridge Rules ─────────────────────────────────────
echo ""
echo "[ EventBridge Rules ] (free — pay per event matched)"
aws events list-rules \
  --region $REGION \
  --query 'Rules[].[Name,State]' \
  --output table 2>/dev/null || echo "  (none)"

# ── SNS Topics ────────────────────────────────────────────
echo ""
echo "[ SNS Topics ] (free tier covers course usage)"
aws sns list-topics \
  --region $REGION \
  --query 'Topics[].TopicArn' \
  --output table 2>/dev/null || echo "  (none)"

# ── Cognito User Pools ────────────────────────────────────
echo ""
echo "[ Cognito User Pools ] (free tier covers 50k MAU)"
aws cognito-idp list-user-pools \
  --max-results 10 \
  --region $REGION \
  --query 'UserPools[].[Name,Id]' \
  --output table 2>/dev/null || echo "  (none)"

# ── Secrets Manager ───────────────────────────────────────
echo ""
echo "[ Secrets Manager ] (~\$0.40/secret/month)"
aws secretsmanager list-secrets \
  --region $REGION \
  --query 'SecretList[].[Name,CreatedDate]' \
  --output table 2>/dev/null || echo "  (none)"

# ── KMS Keys ──────────────────────────────────────────────
echo ""
echo "[ KMS Keys ] (\$1/month per customer-managed key)"
aws kms list-aliases \
  --region $REGION \
  --query "Aliases[?starts_with(AliasName,'alias/photoviewer')].[AliasName,TargetKeyId]" \
  --output table 2>/dev/null || echo "  (none)"

# ── SCPs ──────────────────────────────────────────────────
echo ""
echo "[ Service Control Policies ] (free)"
aws organizations list-policies \
  --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[?Name!=`FullAWSAccess`].[Name,Id]' \
  --output table 2>/dev/null || echo "  (none or Organizations not enabled)"

# ── Identity Center ──────────────────────────────────────
echo ""
echo "[ Identity Center ] (free)"
IC_INSTANCE=$(aws sso-admin list-instances \
  --query 'Instances[0].InstanceArn' \
  --output text 2>/dev/null || echo "NONE")
if [ "$IC_INSTANCE" != "NONE" ] && [ "$IC_INSTANCE" != "None" ] && [ -n "$IC_INSTANCE" ]; then
  echo "  Instance: $IC_INSTANCE"
  aws sso-admin list-permission-sets \
    --instance-arn "$IC_INSTANCE" \
    --query 'PermissionSets' \
    --output text 2>/dev/null | while read PS_ARN; do
      PS_NAME=$(aws sso-admin describe-permission-set \
        --instance-arn "$IC_INSTANCE" \
        --permission-set-arn "$PS_ARN" \
        --query 'PermissionSet.Name' \
        --output text 2>/dev/null || echo "unknown")
      echo "  Permission set: $PS_NAME"
    done
else
  echo "  Not enabled"
fi

# ── IAM Roles (course-related) ───────────────────────────
echo ""
echo "[ IAM Roles — photoviewer/lambda ] (free)"
aws iam list-roles \
  --query "Roles[?contains(RoleName,'photoviewer') || contains(RoleName,'PhotoViewer') || contains(RoleName,'lambda') || contains(RoleName,'Lambda')].[RoleName,CreateDate]" \
  --output table 2>/dev/null || echo "  (none)"

# ── Summary ────────────────────────────────────────────────
echo ""
echo "=============================================="
echo " Cost reminder — things that cost money:"
echo "   NAT Gateway       ~\$32/month"
echo "   ALB               ~\$16/month"
echo "   Interface VPC ep  ~\$7/month each"
echo "   EC2 t3.micro      ~\$8/month (outside free tier)"
echo "   WAF Web ACL       ~\$5/month (custom only — CloudFront-managed is free)"
echo "   Elastic IP        ~\$4/month if unattached"
echo "   AWS Config        ~\$1-2/month (recorder + rules)"
echo "   KMS keys          ~\$1/month per key"
echo "   Secrets Manager   ~\$0.40/secret/month"
echo ""
echo " Free trial (disable after trial ends):"
echo "   GuardDuty         30-day free trial"
echo "   Security Hub      30-day free trial"
echo "   Macie             30-day free trial"
echo "   Inspector         15-day free trial"
echo ""
echo " Safe to leave running (free tier / no cost):"
echo "   VPC, subnets, route tables, IGW, security groups"
echo "   S3, DynamoDB, CloudFront, IAM, Gateway endpoints"
echo "   Lambda, API Gateway, CloudTrail, Cognito"
echo "   EventBridge, SNS, CloudWatch alarms, SCPs"
echo "=============================================="
echo ""
