# Photo Viewer — Week 4
## EC2 Backend in VPC

### What this is
Week 3 with a dynamic backend added. Photo metadata moved from a static `photos.json` file to DynamoDB. A Flask API server running on EC2 in a private VPC subnet serves the photo list dynamically. CloudFront routes `/photos` API requests to an ALB which forwards to EC2.

### What changed from Week 3

| File | What changed |
|---|---|
| `app.js` | One line change — `fetch('/photos.json')` → `fetch('/photos')` |
| `app.py` | New — Flask API server, queries DynamoDB, returns photo list as JSON |
| Everything else | Unchanged from Week 3 |

### Architecture
```
Browser → CloudFront → S3 (static files via OAC)
                    → ALB (public subnet) → EC2 Flask (private subnet) → DynamoDB
```

### What was added from Week 3
- DynamoDB table storing photo metadata dynamically
- VPC with public and private subnets
- ALB in public subnet receiving CloudFront requests
- EC2 running Flask API in private subnet
- SSM Session Manager for remote access — no SSH, no port 22
- VPC endpoints for DynamoDB, S3, and SSM — no internet needed at runtime

### Deliberate vulnerabilities (intentional)
- ALB is internet-facing — anyone who knows the ALB DNS name can bypass CloudFront
- No rate limiting on the `/photos` API endpoint
- No authentication on the API

---

## Prerequisites
- Week 3 fully working — your CloudFront distribution must be serving the Photo Viewer
- AWS CLI configured (see Week 0 setup guide) — needed for the `aws s3 cp` command in the user data script

---

## Part 1 — DynamoDB

### Step 1 — Create the table

Go to **DynamoDB → Tables → Create table:**
- Table name: `photoviewer-photos`
- Partition key: `photo_id` — type: String
- Sort key: leave empty
- Table settings: Default settings
- Click **Create table**

---

### Step 2 — Seed the photo catalog

Go to **DynamoDB → Tables → photoviewer-photos → Explore table items → Create item:**

At the top of the editor toggle **off** "View DynamoDB JSON" — make sure it is disabled. Then paste each item one at a time and click **Create item** after each:

```json
{ "photo_id": "photo-001", "filename": "photo1.jpg", "s3_key": "photos/photo1.jpg", "is_public": true, "owner": "anonymous", "uploaded_at": "2026-04-01T00:00:00Z" }
```
```json
{ "photo_id": "photo-002", "filename": "photo2.jpg", "s3_key": "photos/photo2.jpg", "is_public": true, "owner": "anonymous", "uploaded_at": "2026-04-01T00:00:00Z" }
```
```json
{ "photo_id": "photo-003", "filename": "photo3.jpg", "s3_key": "photos/photo3.jpg", "is_public": true, "owner": "anonymous", "uploaded_at": "2026-04-01T00:00:00Z" }
```
```json
{ "photo_id": "photo-004", "filename": "photo4.jpg", "s3_key": "photos/photo4.jpg", "is_public": true, "owner": "anonymous", "uploaded_at": "2026-04-01T00:00:00Z" }
```
```json
{ "photo_id": "photo-005", "filename": "photo5.jpg", "s3_key": "photos/photo5.jpg", "is_public": true, "owner": "anonymous", "uploaded_at": "2026-04-01T00:00:00Z" }
```

> The `s3_key` field is the path to the photo in S3. Flask returns this to the browser, which uses it to request the photo from CloudFront → S3. If your photos have different names, update the `s3_key` values to match.

---

## Part 2 — Upload app.py to S3

### Step 3 — Upload the Flask application

Go to your S3 bucket → click **Create folder** → name it `app` → **Create folder**

Open the `app` folder → click **Upload** → select `app.py` → **Upload**

**CLI alternative:**
```bash
aws s3 cp app.py s3://photoviewer-[your-account-id]/app/app.py
```

---

## Part 3 — IAM Role

### Step 4 — Create the EC2 IAM role

Go to **IAM → Roles → Create role:**
- Trusted entity type: AWS service
- Use case: EC2
- Click **Next**

Search for and select `AmazonSSMManagedInstanceCore` → click **Next**

- Role name: `photoviewer-ec2-role`
- Click **Create role**

**Add inline policy 1 — DynamoDB read:**

Click on `photoviewer-ec2-role` → **Add permissions → Create inline policy** → switch to JSON editor → paste the following — replace `[your-account-id]`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "dynamodb:Scan",
    "Resource": "arn:aws:dynamodb:us-east-1:[your-account-id]:table/photoviewer-photos"
  }]
}
```
- Policy name: `photoviewer-dynamodb-read`
- Click **Create policy**

**Add inline policy 2 — S3 app read:**

Click **Add permissions → Create inline policy** again → JSON editor → paste — replace `[your-account-id]`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::photoviewer-[your-account-id]/app/*"
  }]
}
```
- Policy name: `photoviewer-s3-app-read`
- Click **Create policy**

Verify the role now has 3 policies: `AmazonSSMManagedInstanceCore`, `photoviewer-dynamodb-read`, `photoviewer-s3-app-read`

---

## Part 4 — VPC

### Step 5 — Create the VPC

Go to **VPC → Create VPC** → select **VPC and more:**
- Name tag: `photoviewer`
- IPv4 CIDR: `10.0.0.0/16`
- Number of Availability Zones: 1
- NAT gateways: None
- VPC endpoints: None
- Click **Create VPC**

**After creation — rename the route tables:**
- VPC → Route tables → find the route table named `photoviewer-rtb-private1-us-east-1a` → click the pencil icon → rename to `photoviewer-rtb-private`
- Leave `photoviewer-rtb-public` as-is

**Create a second public subnet** (required by ALB):

Go to **VPC → Subnets → Create subnet:**
- VPC: `photoviewer-vpc`
- Subnet name: `photoviewer-subnet-public2-us-east-1b`
- Availability Zone: us-east-1b
- IPv4 CIDR: `10.0.16.0/20`
- Click **Create subnet**

Associate it with the public route table:
- VPC → Route tables → `photoviewer-rtb-public` → **Subnet associations** → **Edit subnet associations** → check `photoviewer-subnet-public2-us-east-1b` → **Save**

---

### Step 6 — Create security groups

Create 3 security groups in this order — each references the previous one.

**SG 1 — photoviewer-alb-sg:**

VPC → Security groups → **Create security group:**
- Name: `photoviewer-alb-sg`
- VPC: `photoviewer-vpc`
- Description: attaches to ALB
- Inbound rules: Add rule → Type: HTTP → Port: 80 → Source: `0.0.0.0/0`
- Click **Create security group**

**SG 2 — photoviewer-ec2-sg:**

Create security group:
- Name: `photoviewer-ec2-sg`
- VPC: `photoviewer-vpc`
- Description: attaches to EC2 instance
- Inbound rules: Add rule → Type: Custom TCP → Port: 8000 → Source: select `photoviewer-alb-sg`
- Click **Create security group**

**SG 3 — photoviewer-endpoint-sg:**

Create security group:
- Name: `photoviewer-endpoint-sg`
- VPC: `photoviewer-vpc`
- Description: attaches to SSM interface endpoints
- Inbound rules: Add rule → Type: HTTPS → Port: 443 → Source: select `photoviewer-ec2-sg`
- Click **Create security group**

---

### Step 7 — Create VPC endpoints

Go to **VPC → Endpoints → Create endpoint.** Create all 5 in order:

**Endpoint 1 — DynamoDB (Gateway, free):**
- Service: search `dynamodb` → select `com.amazonaws.us-east-1.dynamodb` (Gateway type)
- VPC: `photoviewer-vpc`
- Route tables: check `photoviewer-rtb-private`
- Click **Create endpoint**

**Endpoint 2 — S3 (Gateway, free):**
- Service: search `s3` → select `com.amazonaws.us-east-1.s3` (Gateway type)
- VPC: `photoviewer-vpc`
- Route tables: check `photoviewer-rtb-private`
- Click **Create endpoint**

**Endpoints 3, 4, 5 — SSM (Interface type):**

Create one endpoint for each of these services — same settings for all three:
- `com.amazonaws.us-east-1.ssm`
- `com.amazonaws.us-east-1.ssmmessages`
- `com.amazonaws.us-east-1.ec2messages`

For each:
- Type: Interface
- VPC: `photoviewer-vpc`
- Subnets: select `photoviewer-subnet-private1-us-east-1a`
- Enable DNS name: **checked**
- Security group: `photoviewer-endpoint-sg` (remove default)
- Click **Create endpoint**

Wait for all 5 endpoints to show **Available** status.

---

## Part 5 — NAT Gateway (temporary)

> The NAT Gateway is needed only during EC2 bootstrap to download Python packages. Delete it in Step 17 after EC2 is running. It costs ~$32/month.

### Step 8 — Create NAT Gateway

Go to **VPC → NAT Gateways → Create NAT gateway:**
- Name: `photoviewer-nat`
- Subnet: `photoviewer-subnet-public1-us-east-1a`
- Connectivity type: Public
- Click **Allocate Elastic IP** → click **Create NAT gateway**

Wait for status to show **Available** (~1 minute).

**Add route to private route table:**

VPC → Route tables → `photoviewer-rtb-private` → **Routes** → **Edit routes** → **Add route:**
- Destination: `0.0.0.0/0`
- Target: NAT Gateway → select `photoviewer-nat`
- Click **Save changes**

---

## Part 6 — ALB

### Step 9 — Create the Application Load Balancer

Go to **EC2 → Load Balancers → Create load balancer → Application Load Balancer:**

- Name: `photoviewer-alb`
- Scheme: Internet-facing
- IP address type: IPv4
- VPC: `photoviewer-vpc`
- Availability Zones: check both `us-east-1a` (select public subnet) and `us-east-1b` (select public subnet)
- Security groups: remove default → add `photoviewer-alb-sg`

**Listener:**
- Protocol: HTTP — Port: 80

**Create target group** (click the link to open in new tab):
- Target type: Instances
- Target group name: `photoviewer-tg`
- Protocol: HTTP — Port: 8000
- VPC: `photoviewer-vpc`
- Health check path: `/health`
- Click **Next → Create target group** (leave targets empty for now)

Back on the ALB page — refresh and select `photoviewer-tg` as the target group.

Click **Create load balancer.**

Note the **DNS name** — you will need it when configuring CloudFront. It looks like:
```
photoviewer-alb-XXXXXXXXXX.us-east-1.elb.amazonaws.com
```

---

## Part 7 — EC2 Instance

### Step 10 — Launch EC2 with user data

Go to **EC2 → Instances → Launch instances:**

- Name: `photoviewer-ec2`
- AMI: Amazon Linux 2023 (free tier eligible)
- Instance type: t3.micro
- Key pair: **Proceed without a key pair** — SSM handles all access

**Network settings:**
- VPC: `photoviewer-vpc`
- Subnet: `photoviewer-subnet-private1-us-east-1a`
- Auto-assign public IP: **Disable**
- Security group: select existing → `photoviewer-ec2-sg`

**Advanced details:**
- IAM instance profile: `photoviewer-ec2-role`
- User data: paste the following — replace `[your-account-id]`:

```bash
#!/bin/bash
dnf update -y
dnf install -y python3-pip
pip3 install flask boto3

mkdir -p /home/ec2-user/photoviewer
aws s3 cp s3://photoviewer-[your-account-id]/app/app.py /home/ec2-user/photoviewer/app.py
chown -R ec2-user:ec2-user /home/ec2-user/photoviewer

cat > /etc/systemd/system/photoviewer.service << 'SVCEOF'
[Unit]
Description=Photo Viewer Flask API
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user/photoviewer
ExecStart=/usr/bin/python3 app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable photoviewer
systemctl start photoviewer
```

Click **Launch instance.** Wait for 2/2 status checks to pass (~3-5 minutes).

---

### Step 11 — Verify Flask is running

Go to **EC2 → Instances → select `photoviewer-ec2`** → **Actions → Monitor and troubleshoot → Get system log**

Scroll to the bottom. Look for:
```
* Running on http://0.0.0.0:8000
```

Alternatively connect via **Systems Manager → Session Manager → Start session → photoviewer-ec2:**
```bash
sudo systemctl status photoviewer
```
Should show `Active: active (running)`.

---

### Step 12 — Register EC2 with the target group

Go to **EC2 → Target Groups → photoviewer-tg → Targets tab → Register targets:**
- Select `photoviewer-ec2` → Port: 8000 → **Include as pending below**
- Click **Register pending targets**

Wait for Health status to show **Healthy** (~1 minute).

---

## Part 8 — Wire CloudFront to ALB

### Step 13 — Add ALB as a second CloudFront origin

Go to **CloudFront → your distribution → Origins tab → Create origin:**
- Origin domain: paste your ALB DNS name
- Protocol: HTTP only
- HTTP port: 80
- Name: `photoviewer-alb-origin`
- Click **Create origin**

---

### Step 14 — Add cache behavior for /photos

Go to **Behaviors tab → Create behavior:**
- Path pattern: `/photos`
- Origin: `photoviewer-alb-origin`
- Viewer protocol policy: Redirect HTTP to HTTPS
- Cache policy: `CachingDisabled`
- Click **Create behavior**

---

### Step 15 — Upload updated app.js to S3

Upload the Week 4 `app.js` to your S3 bucket root — replacing the Week 3 version:

Go to your bucket → **Upload** → select `app.js` → **Upload**

**CLI alternative:**
```bash
aws s3 cp app.js s3://photoviewer-[your-account-id]/
```

Then create a `/*` CloudFront invalidation.

---

## Part 9 — Verify and clean up

### Step 16 — Verify end-to-end

Browse to your CloudFront URL. The Photo Viewer should load photos dynamically from DynamoDB.

Open **DevTools → Network tab** → click the `/photos` request → **Response Headers.** Confirm:
- `Server: Werkzeug/x.x.x Python/x.x.x` — proves response came from Flask on EC2 ✅
- `Via: ... (CloudFront)` — proves CloudFront forwarded the request ✅
- `X-Cache: Miss from cloudfront` — confirms caching is disabled for API responses ✅

---

### Step 17 — Delete NAT Gateway

> Do this immediately after verifying everything works.

1. **VPC → NAT Gateways** → select `photoviewer-nat` → **Actions → Delete NAT gateway** → confirm
2. **VPC → Route tables → `photoviewer-rtb-private` → Routes → Edit routes** → delete the `0.0.0.0/0 → nat-gateway` route → **Save changes**
3. **VPC → Elastic IPs** → select the EIP that was associated with the NAT Gateway → **Actions → Release Elastic IP address** → confirm

Verify the private route table now has only two routes:
- `10.0.0.0/16 → local`
- The DynamoDB and S3 prefix list entries from the Gateway endpoints
