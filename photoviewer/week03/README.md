# Photo Viewer — Week 3
## CloudFront + Edge Security

### What this is
Week 2 with CloudFront added in front of S3. S3 bucket is now fully private. HTTPS enforced. A CloudFront Function blocks non-web file types at the edge. Security response headers added.

### What changed from Week 2

| File | What changed |
|---|---|
| `app.js` | Now fetches `/photos.json` via relative path — works for both S3 and CloudFront |
| `photos.json` | New file — static photo list served by CloudFront |
| `photoviewer-allowlist.js` | New — CloudFront Function that blocks non-web file types |
| `index.html`, `style.css`, `confidential.txt` | Unchanged |

### Architecture
```
Browser → CloudFront (HTTPS) → S3 (private, OAC)
              ↓
       CF Function (allowlist) runs at edge
       Response Headers Policy adds HSTS, X-Frame-Options
```

### What was fixed from Week 2
1. ✅ HTTPS enforced — CloudFront redirects HTTP to HTTPS automatically
2. ✅ S3 bucket private — OAC restricts access to CloudFront only
3. ✅ Non-web files blocked — CF Function allowlist returns 403 at the edge
4. ✅ Global edge caching — 400+ CloudFront POPs worldwide
5. ✅ Bucket enumeration blocked — structurally impossible through CloudFront

---

## Deployment steps

### Step 1 — Upload new files to S3

Upload the updated `app.js` and new `photos.json` to your S3 bucket root:

Go to your bucket → click **Upload** → add `app.js` and `photos.json` → **Upload**

> When prompted about overwriting the existing `app.js` — confirm the overwrite.

**CLI alternative:**
```bash
aws s3 cp app.js s3://photoviewer-[your-account-id]/
aws s3 cp photos.json s3://photoviewer-[your-account-id]/
```

---

### Step 2 — Disable static website hosting

Go to your bucket → **Properties tab** → **Static website hosting** → click **Edit:**
- Static website hosting: **Disable**
- Click **Save changes**

---

### Step 3 — Enable Block Public Access

Go to your bucket → **Permissions tab** → **Block public access** → click **Edit:**
- Check all four boxes
- Click **Save changes** → type `confirm` → **Confirm**

Then delete the bucket policy:
- Still on Permissions tab → **Bucket policy** → click **Edit** → delete all content → **Save changes**

---

### Step 4 — Create CloudFront distribution

Go to **CloudFront → Distributions → Create distribution:**

**Origin settings:**
- Origin domain: select your S3 bucket from the dropdown
- When prompted "Allow private S3 bucket access to CloudFront?" → click **Yes, update the bucket policy**
- This creates OAC automatically and updates the bucket policy

**Default cache behavior:**
- Viewer protocol policy: **Redirect HTTP to HTTPS**
- Cache policy: leave as default

**Settings:**
- Default root object: `index.html`
- WAF: leave disabled

Click **Create distribution** and wait for Status to show **Enabled** (~2 minutes).

---

### Step 5 — Create the CloudFront Function

Go to **CloudFront → Functions → Create function:**
- Name: `photoviewer-allowlist`
- Runtime: cloudfront-js-2.0
- Paste the code from `photoviewer-allowlist.js`
- Click **Save changes** → **Publish**

**Attach the function to the distribution:**
- Go to your distribution → **Behaviors tab** → select the default behavior → **Edit**
- Function associations → Viewer request → select `photoviewer-allowlist`
- Click **Save changes**

---

### Step 6 — Add Security Response Headers Policy

Still editing the default behavior:
- Response headers policy → select **SecurityHeadersPolicy** (AWS managed)
- Click **Save changes**

---

### Step 7 — Invalidate the cache

Go to your distribution → **Invalidations tab** → **Create invalidation:**
- Object paths: `/*`
- Click **Create invalidation**

Wait for the invalidation to complete (~30 seconds).

---

### Step 8 — Verify

Copy your CloudFront distribution domain name (looks like `d1kbm2nphud61r.cloudfront.net`) from the distribution details page.

Open it in your browser:
- Photo Viewer loads over HTTPS ✅ — padlock visible in browser
- Navigate to `[your-cf-domain]/confidential.txt` → returns **403 Forbidden** ✅
- Navigate to `http://[your-cf-domain]` → automatically redirects to HTTPS ✅

Open DevTools → Network tab → click any request → Response Headers:
- `Strict-Transport-Security` header present ✅
- `X-Frame-Options` header present ✅
- `X-Content-Type-Options` header present ✅

**Verify bucket enumeration is blocked:**
```bash
aws s3 ls s3://photoviewer-[your-account-id] --no-sign-request
```
This should now return **Access Denied** ✅
