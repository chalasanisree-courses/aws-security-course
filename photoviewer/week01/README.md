# Week 0 — AWS CLI Setup

This page covers how to install and configure the AWS CLI so you can run commands from your terminal. This is optional — all labs can be completed using the AWS Console UI. The CLI is provided as an alternative for students who prefer working from the terminal.

---

## Step 1 — Create an IAM user with access keys

The AWS CLI needs credentials to authenticate your requests. We will create a dedicated IAM user with access keys for this purpose.

Go to **IAM → Users → Create user:**
- User name: `cs55d-cli-user`
- Check **Provide user access to the AWS Management Console**: No — leave unchecked
- Click **Next**

**Attach permissions:**
- Select **Attach policies directly**
- Search for and select `AdministratorAccess`
- Click **Next → Create user**

> **Note:** `AdministratorAccess` gives full access to your AWS account. This is acceptable for a personal student account used only for this course. In a real enterprise you would use least privilege — only the permissions needed for each task.

**Create access keys:**
- Click on your new user `cs55d-cli-user`
- Go to the **Security credentials** tab
- Scroll to **Access keys** → click **Create access key**
- Use case: **Command Line Interface (CLI)**
- Check the confirmation box → click **Next → Create access key**
- **Copy both the Access Key ID and Secret Access Key now** — the secret key is only shown once
- Store them somewhere safe — treat them like a password

> **Security warning:** Never share your access keys. Never paste them into code or commit them to GitHub. If you accidentally expose them, go to IAM immediately and delete them, then create new ones.

---

## Step 2 — Install the AWS CLI

**Mac:**
```bash
brew install awscli
```
Or download the installer from: https://aws.amazon.com/cli/

**Windows:**
Download and run the MSI installer from: https://aws.amazon.com/cli/

**Linux:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Verify installation:**
```bash
aws --version
```
You should see something like: `aws-cli/2.x.x Python/3.x.x`

---

## Step 3 — Configure the CLI

Run the following command and enter your credentials when prompted:

```bash
aws configure
```

```
AWS Access Key ID: [paste your Access Key ID]
AWS Secret Access Key: [paste your Secret Access Key]
Default region name: us-east-1
Default output format: json
```

Your credentials are stored in `~/.aws/credentials` on Mac/Linux or `C:\Users\USERNAME\.aws\credentials` on Windows.

---

## Step 4 — Verify it works

```bash
aws sts get-caller-identity
```

You should see your account ID and user ARN:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "644094189785",
    "Arn": "arn:aws:iam::644094189785:user/cs55d-cli-user"
}
```

If this works, your CLI is correctly configured and ready to use.

---

## Using the CLI in labs

Each week's README includes optional CLI commands alongside the console UI instructions. You can use either approach — the end result is identical.

When a lab instruction says:
> **Go to S3 → Create bucket**

The CLI equivalent will be shown as:
> **CLI alternative:** `aws s3 mb s3://bucket-name --region us-east-1`

You do not need to do both — pick one approach per lab and stick with it.
