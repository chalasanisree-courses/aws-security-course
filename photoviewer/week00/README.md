# Week 0 — CLI Setup

This page covers how to run AWS CLI commands for the labs. All labs can be completed using the AWS Console UI — the CLI is provided as a faster alternative for repeated operations.

There are two ways to use the CLI. **Option A (CloudShell) is recommended** — it requires zero setup.

---

## Option A — AWS CloudShell (recommended)

CloudShell is a browser-based terminal built into the AWS Console. It has the AWS CLI pre-installed and is already authenticated as whoever is logged into the console. No credentials, no installation, nothing to configure.

**How to open it:**
1. Log into the AWS Console as your IAM admin user
2. Make sure the region selector in the top-right shows **us-east-1**
3. Click the **>_** icon in the top navigation bar (next to the search bar)
4. A terminal opens at the bottom of the screen — that is CloudShell

**Verify it works:**
```bash
aws sts get-caller-identity
```

You should see your account ID and IAM admin user ARN. If you do, you are ready.

**Clone the course repo (do this once):**
```bash
git clone https://github.com/chalasanisree-courses/aws-security-course.git
```

CloudShell persists your home directory between sessions — you only need to clone once.

**Get updates each week before starting the lab:**
```bash
cd aws-security-course
git pull
```

**Run the resource audit script any time:**
```bash
bash aws-security-course/photoviewer/audit-aws-resources.sh
```

> **Note on file uploads:** CloudShell's file upload feature can be unreliable for `.sh` files. Use `git clone` / `git pull` instead of uploading files directly.

---

## Option B — Local CLI (optional)

Use this only if you want to run AWS CLI commands from your own computer. Requires installation and credential setup — skip this if CloudShell works for you.

### Step 1 — Create access keys

Go to **IAM → Users → Create user:**
- User name: `cs55d-cli-user`
- **Provide user access to the AWS Management Console**: leave unchecked
- Click **Next → Attach policies directly → AdministratorAccess → Next → Create user**

**Create access keys:**
- Click on `cs55d-cli-user` → **Security credentials** tab → **Access keys → Create access key**
- Use case: **Command Line Interface (CLI)** → confirm → **Create access key**
- **Copy both the Access Key ID and Secret Access Key now** — the secret key is only shown once

> **Security warning:** Never share your access keys. Never paste them into code or commit them to GitHub. If you accidentally expose them, delete them in IAM immediately and create new ones.

### Step 2 — Install the AWS CLI

**Mac:** `brew install awscli`  
**Windows:** Download MSI from https://aws.amazon.com/cli/  
**Linux:** Follow instructions at https://aws.amazon.com/cli/

Verify: `aws --version`

### Step 3 — Configure

```bash
aws configure
```
Enter your Access Key ID, Secret Access Key, region `us-east-1`, output format `json`.

### Step 4 — Verify

```bash
aws sts get-caller-identity
```

Then clone the repo:
```bash
git clone https://github.com/chalasanisree-courses/aws-security-course.git
```

---

## Using the CLI in labs

Each week's README includes CLI commands alongside console UI steps. Pick one approach per lab — the result is identical either way.

**CloudShell vs local CLI:** The only difference is where the terminal runs. Both run the same commands. CloudShell is simpler — no setup, always up to date, authenticated automatically.
