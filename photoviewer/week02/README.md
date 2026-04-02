# Photo Viewer — Week 2
## Static S3 Hosting

### What this is
A simple static photo viewer hosted directly from an S3 bucket with static website hosting enabled. This is the deliberately insecure starting point for the course.

### Files in this folder

| File | Purpose |
|---|---|
| `index.html` | Main page — Photo Viewer UI |
| `style.css` | Styles |
| `app.js` | Fetches `photos.json` and cycles through photos |
| `photos.json` | Static list of photos — update if you rename your photos |
| `confidential.txt` | Deliberately exposed sensitive file — demonstrates the vulnerability |

### Architecture
```
Browser → S3 website endpoint (HTTP only)
```

### Deliberate vulnerabilities (intentional)
1. HTTP only — S3 website endpoint has no TLS
2. Public bucket — `confidential.txt` accessible to anyone who knows the path
3. Bucket enumerable — anyone can list all files without credentials
4. No caching — every request travels to us-east-1

These are all fixed in Week 3.

---

## Deployment steps

### Step 1 — Create an S3 bucket

Go to **S3 → Buckets → Create bucket:**
- Bucket name: `photoviewer-[your-account-id]` — use your 12-digit AWS account ID to make it globally unique. Find your account ID in the top-right corner of the AWS console.
- AWS Region: US East (N. Virginia) us-east-1
- Leave all other settings as default
- Click **Create bucket**

**CLI alternative:**
```bash
aws s3 mb s3://photoviewer-[your-account-id] --region us-east-1
```

---

### Step 2 — Enable static website hosting

Go to your bucket → **Properties tab** → scroll to **Static website hosting** → click **Edit:**
- Static website hosting: **Enable**
- Hosting type: Host a static website
- Index document: `index.html`
- Click **Save changes**

**CLI alternative:**
```bash
aws s3 website s3://photoviewer-[your-account-id] --index-document index.html
```

---

### Step 3 — Make the bucket public (intentionally insecure)

**First — disable Block Public Access:**

Go to your bucket → **Permissions tab** → **Block public access (bucket settings)** → click **Edit:**
- Uncheck all four boxes
- Click **Save changes** → type `confirm` → **Confirm**

**CLI alternative:**
```bash
aws s3api put-public-access-block \
  --bucket photoviewer-[your-account-id] \
  --public-access-block-configuration \
  "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
```

**Second — create a bucket policy:**

Still on the Permissions tab → **Bucket policy** → click **Edit** → paste the following — replace `[your-account-id]`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::photoviewer-[your-account-id]",
      "arn:aws:s3:::photoviewer-[your-account-id]/*"
    ]
  }]
}
```

Click **Save changes.**

> **Note:** `s3:ListBucket` is included intentionally — this allows bucket enumeration which is the vulnerability demonstrated at the end of this lab.

**CLI alternative** — save the JSON above as `bucket-policy.json` then:
```bash
aws s3api put-bucket-policy \
  --bucket photoviewer-[your-account-id] \
  --policy file://bucket-policy.json
```

---

### Step 4 — Add your photos

**Create the photos folder:**

Go to your bucket → click **Create folder** → name it `photos` → **Create folder**

**Upload your photos:**

Open the `photos` folder → click **Upload** → add 5 photo files.

Name them `photo1.jpg` through `photo5.jpg`. If you use different filenames update `photos.json` to match — the `s3_key` field must match the actual filename in S3.

**CLI alternative:**
```bash
aws s3 cp photos/ s3://photoviewer-[your-account-id]/photos/ --recursive
```

---

### Step 5 — Upload all website files

Go to your bucket root (not inside the `photos/` folder) → click **Upload** → add these files:
- `index.html`
- `style.css`
- `app.js`
- `photos.json`
- `confidential.txt`

Click **Upload.**

> **Important:** `confidential.txt` must be at the bucket root alongside `index.html` — this is the file that demonstrates the vulnerability.

**CLI alternative:**
```bash
aws s3 cp index.html s3://photoviewer-[your-account-id]/
aws s3 cp style.css s3://photoviewer-[your-account-id]/
aws s3 cp app.js s3://photoviewer-[your-account-id]/
aws s3 cp photos.json s3://photoviewer-[your-account-id]/
aws s3 cp confidential.txt s3://photoviewer-[your-account-id]/
```

---

### Step 6 — Access the site

Go to your bucket → **Properties tab** → scroll to **Static website hosting** → copy the **Bucket website endpoint.** It will look like:

```
http://photoviewer-[your-account-id].s3-website-us-east-1.amazonaws.com
```

Open it in your browser — the Photo Viewer should load and cycle through your photos.

---

## Demonstrating the vulnerabilities

**Access the confidential file directly:**

Navigate to:
```
http://photoviewer-[your-account-id].s3-website-us-east-1.amazonaws.com/confidential.txt
```
The file is readable without any authentication.

**Confirm HTTP only:**
Note the URL starts with `http://` — no padlock. Open DevTools → Network tab and confirm no TLS.

**Enumerate the bucket without credentials:**
```bash
aws s3 ls s3://photoviewer-[your-account-id] --no-sign-request
```
This lists all files in the bucket without logging in — including files you never intended to expose.
