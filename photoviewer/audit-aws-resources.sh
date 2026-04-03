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

# ── CloudTrail ─────────────────────────────────────────────
echo ""
echo "[ CloudTrail Trails ]"
aws cloudtrail describe-trails \
  --region $REGION \
  --query 'trailList[].[Name,S3BucketName,IsLogging]' \
  --output table 2>/dev/null || echo "  (none)"

# ── Summary ────────────────────────────────────────────────
echo ""
echo "=============================================="
echo " Cost reminder — things that cost money:"
echo "   NAT Gateway       ~\$32/month"
echo "   ALB               ~\$16/month"
echo "   Interface VPC ep  ~\$7/month each"
echo "   EC2 t3.micro      ~\$8/month (outside free tier)"
echo "   Elastic IP        ~\$4/month if unattached"
echo ""
echo " Safe to leave running (free tier):"
echo "   VPC, subnets, route tables, IGW, security groups"
echo "   S3, DynamoDB, CloudFront, IAM, Gateway endpoints"
echo "=============================================="
echo ""
