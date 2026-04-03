# Week 1 — AWS Account Setup

This README covers the CLI commands for Week 1 tasks. All steps can also be done in the AWS Console — see the Week 1 lab assignment on Canvas for full instructions.

> **New to the CLI?** See [Week 0 CLI Setup](../week00/README.md) first.  
> **Recommended:** Use AWS CloudShell — click the **>_** icon in the AWS Console top bar. No setup needed.

---

## Verify you are logged in as IAM admin (not root)

```bash
aws sts get-caller-identity
```

The `Arn` field should show your IAM admin user — not `root`. Example:
```
arn:aws:iam::123456789012:user/admin
```

If it shows `root`, log out and log back in as your IAM admin user.

---

## Check CloudTrail is enabled

```bash
aws cloudtrail describe-trails \
  --region us-east-1 \
  --query 'trailList[].[Name,S3BucketName,IsLogging]' \
  --output table
```

You should see `photoviewer-trail` with `IsLogging: true`.

---

## Check billing alarm exists

```bash
# Billing metrics are only in us-east-1
aws cloudwatch describe-alarms \
  --region us-east-1 \
  --query 'MetricAlarms[].[AlarmName,StateValue,Threshold]' \
  --output table
```

You should see your billing alarm with a $10 threshold.

---

## Run the resource audit script

Clone the course repo into CloudShell (first time only):
```bash
git clone https://github.com/chalasanisree-courses/aws-security-course.git
```

Run the audit:
```bash
bash aws-security-course/photoviewer/audit-aws-resources.sh
```

This shows all running resources and what they cost. Run it at the end of every lab to make sure you haven't left anything expensive running.
