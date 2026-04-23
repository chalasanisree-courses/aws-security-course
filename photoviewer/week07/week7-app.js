/**
 * Photo Viewer — app.js (Week 7)
 *
 * Changes from Week 6:
 *   - Parses cognito:groups and sub from JWT to determine premium status and identity
 *   - Upload: premium users get an upload form; POST /photos returns presigned PUT URL;
 *     browser uploads file bytes directly to S3
 *   - Delete: premium users see delete button on their own photos;
 *     DELETE /photos/{photoId} removes from S3 + DynamoDB
 *   - Toggle: premium users see visibility toggle on their own photos;
 *     PATCH /photos/{photoId} flips is_public
 *   - Photo rendering: uses photo.url from API response (presigned S3 URL
 *     for all photos — pre-seeded and uploaded) instead of constructing from s3_key
 *
 * BEFORE DEPLOYING — replace these three placeholders:
 *   YOUR_COGNITO_DOMAIN    Cognito → User pool → App integration → Domain
 *                          (the prefix before .auth.us-east-1.amazoncognito.com,
 *                           e.g. us-east-1abcdefgh)
 *   YOUR_APP_CLIENT_ID     Cognito → User pool → App integration → App clients
 *                          (e.g. 7ilrlh8hpfoj87i8vtncfp126b)
 *   YOUR_CLOUDFRONT_DOMAIN Your CloudFront distribution domain
 *                          (e.g. d1kbm2nphud61r.cloudfront.net)
 */

// ── Configuration ─────────────────────────────────────────────────────────────

const COGNITO_DOMAIN    = 'YOUR_COGNITO_DOMAIN';
const APP_CLIENT_ID     = 'YOUR_APP_CLIENT_ID';
const CLOUDFRONT_DOMAIN = 'YOUR_CLOUDFRONT_DOMAIN';

const COGNITO_BASE      = `https://${COGNITO_DOMAIN}.auth.us-east-1.amazoncognito.com`;
const REDIRECT_URI      = `https://${CLOUDFRONT_DOMAIN}/callback`;
const LOGOUT_URI        = `https://${CLOUDFRONT_DOMAIN}`;
const TOKEN_KEY         = 'pv_id_token';
const VERIFIER_KEY      = 'pv_code_verifier';


// ── PKCE helpers ──────────────────────────────────────────────────────────────

function base64urlEncode(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function generateCodeVerifier() {
  const array = new Uint8Array(48);
  crypto.getRandomValues(array);
  return base64urlEncode(array);
}

async function generateCodeChallenge(verifier) {
  const encoded  = new TextEncoder().encode(verifier);
  const digest   = await crypto.subtle.digest('SHA-256', encoded);
  return base64urlEncode(digest);
}


// ── Token helpers ─────────────────────────────────────────────────────────────

function getToken() {
  return sessionStorage.getItem(TOKEN_KEY);
}

function clearToken() {
  sessionStorage.removeItem(TOKEN_KEY);
  sessionStorage.removeItem(VERIFIER_KEY);
}

function isTokenExpired(token) {
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return Date.now() >= payload.exp * 1000;
  } catch {
    return true;
  }
}

function getTokenPayload(token) {
  try {
    return JSON.parse(atob(token.split('.')[1]));
  } catch {
    return {};
  }
}

function getUserEmail(token) {
  return getTokenPayload(token).email || null;
}

function getUserSub(token) {
  return getTokenPayload(token).sub || '';
}

function getUserGroups(token) {
  return getTokenPayload(token)['cognito:groups'] || [];
}

function isPremium(token) {
  return getUserGroups(token).includes('premium');
}


// ── Auth flow ─────────────────────────────────────────────────────────────────

async function login() {
  const verifier   = generateCodeVerifier();
  const challenge  = await generateCodeChallenge(verifier);

  sessionStorage.setItem(VERIFIER_KEY, verifier);

  const url = new URL(`${COGNITO_BASE}/oauth2/authorize`);
  url.searchParams.set('response_type',          'code');
  url.searchParams.set('client_id',              APP_CLIENT_ID);
  url.searchParams.set('redirect_uri',           REDIRECT_URI);
  url.searchParams.set('scope',                  'openid email profile');
  url.searchParams.set('code_challenge',         challenge);
  url.searchParams.set('code_challenge_method',  'S256');
  window.location.href = url.toString();
}

function logout() {
  clearToken();
  const url = new URL(`${COGNITO_BASE}/logout`);
  url.searchParams.set('client_id',  APP_CLIENT_ID);
  url.searchParams.set('logout_uri', LOGOUT_URI);
  window.location.href = url.toString();
}

async function exchangeCodeForToken(code) {
  const verifier = sessionStorage.getItem(VERIFIER_KEY);
  if (!verifier) throw new Error('No code_verifier found');

  const body = new URLSearchParams({
    grant_type:    'authorization_code',
    client_id:     APP_CLIENT_ID,
    redirect_uri:  REDIRECT_URI,
    code:          code,
    code_verifier: verifier
  });

  const resp = await fetch(`${COGNITO_BASE}/oauth2/token`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    body.toString()
  });

  if (!resp.ok) {
    const err = await resp.text();
    throw new Error(`Token exchange failed: ${err}`);
  }

  const data = await resp.json();
  return data.id_token;
}

async function handleCallback() {
  const params = new URLSearchParams(window.location.search);
  const code   = params.get('code');
  if (!code) return false;

  try {
    const token = await exchangeCodeForToken(code);
    sessionStorage.setItem(TOKEN_KEY, token);
  } catch (e) {
    console.error('Auth callback error:', e);
  }

  window.history.replaceState({}, document.title, '/');
  window.location.reload();
  return true;
}


// ── API helpers ───────────────────────────────────────────────────────────────

function authHeaders() {
  const token   = getToken();
  const headers = { 'Content-Type': 'application/json' };
  if (token && !isTokenExpired(token)) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  return headers;
}


// ── UI rendering ──────────────────────────────────────────────────────────────

function renderAuthButton() {
  const token = getToken();
  const btn   = document.getElementById('auth-btn');
  const label = document.getElementById('auth-btn-label');
  const icon  = btn ? btn.querySelector('.btn-google-icon') : null;
  if (!btn || !label) return;

  if (token && !isTokenExpired(token)) {
    const email = getUserEmail(token);
    label.textContent = 'Sign out';
    btn.onclick = logout;

    // Replace Google "G" with user's initial
    if (icon && email) {
      const initial = email.charAt(0).toUpperCase();
      icon.innerHTML = `<span class="user-initial">${initial}</span>`;
    }
  } else {
    label.textContent = 'Sign in with Google';
    btn.onclick = login;
  }
}

function renderPremiumControls() {
  const token     = getToken();
  const uploadBar = document.getElementById('upload-bar');
  if (!uploadBar) return;

  if (token && !isTokenExpired(token) && isPremium(token)) {
    uploadBar.style.display = 'flex';
  } else {
    uploadBar.style.display = 'none';
  }
}

function renderPhotoControls(photo) {
  const token      = getToken();
  const controls   = document.getElementById('photo-controls');
  if (!controls) return;

  const sub = token ? getUserSub(token) : '';
  const isOwner = photo.owner && photo.owner === sub;
  const premium = token && isPremium(token);

  if (premium && isOwner) {
    controls.style.display = 'flex';

    // Toggle button
    const toggleBtn = document.getElementById('btn-toggle');
    if (toggleBtn) {
      toggleBtn.title = photo.is_public ? 'Make private' : 'Make public';
      toggleBtn.innerHTML = photo.is_public
        ? '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>'
        : '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19m-6.72-1.07a3 3 0 11-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>';
      toggleBtn.onclick = () => toggleVisibility(photo.photo_id, !photo.is_public);
    }

    // Delete button
    const deleteBtn = document.getElementById('btn-delete');
    if (deleteBtn) {
      deleteBtn.onclick = () => deletePhoto(photo.photo_id);
    }
  } else {
    controls.style.display = 'none';
  }
}


// ── Photos ────────────────────────────────────────────────────────────────────

async function loadPhotos() {
  const token = getToken();

  // If token exists but has expired, clear and reload
  if (token && isTokenExpired(token)) {
    clearToken();
    window.location.reload();
    return;
  }

  const resp = await fetch('/photos', { headers: authHeaders() });
  if (!resp.ok) {
    console.error('Failed to load photos:', resp.status);
    return;
  }

  const photos = await resp.json();

  window._photos       = photos;
  window._currentIndex = photos.length > 0 ? 0 : -1;

  if (photos.length > 0) {
    showPhoto(0);
  }

  // Update counter
  const counter = document.getElementById('counter');
  if (counter) {
    counter.textContent = photos.length > 0
      ? `1 of ${photos.length}`
      : 'No photos';
  }
}

function showPhoto(index) {
  const photos  = window._photos || [];
  const img     = document.getElementById('photo');
  const counter = document.getElementById('counter');
  const title   = document.getElementById('photo-title');
  if (!img || photos.length === 0) return;

  const photo = photos[index];

  // Use the url field from the API response
  img.src = photo.url;
  img.alt = photo.title || photo.photo_id;

  if (counter) counter.textContent = `${index + 1} of ${photos.length}`;
  if (title)   title.textContent   = photo.title || '';

  // Show/hide owner controls
  renderPhotoControls(photo);
}

function nextPhoto() {
  const photos = window._photos || [];
  if (photos.length === 0) return;
  window._currentIndex = (window._currentIndex + 1) % photos.length;
  showPhoto(window._currentIndex);
}


// ── Upload ────────────────────────────────────────────────────────────────────

async function uploadPhoto() {
  const fileInput = document.getElementById('upload-file');
  const titleInput = document.getElementById('upload-title');
  const publicCheck = document.getElementById('upload-public');
  const status = document.getElementById('upload-status');

  if (!fileInput || !fileInput.files[0]) {
    if (status) status.textContent = 'Please select a file';
    return;
  }

  const file = fileInput.files[0];
  const photoTitle = titleInput ? titleInput.value.trim() || 'Untitled' : 'Untitled';
  const isPublic = publicCheck ? publicCheck.checked : true;

  if (status) status.textContent = 'Requesting upload URL...';

  try {
    // Step 1: Get presigned PUT URL from Lambda
    const resp = await fetch('/photos', {
      method:  'POST',
      headers: authHeaders(),
      body:    JSON.stringify({ title: photoTitle, is_public: isPublic, content_type: file.type })
    });

    if (!resp.ok) {
      const err = await resp.json();
      if (status) status.textContent = `Error: ${err.error || resp.status}`;
      return;
    }

    const { uploadUrl, photoId } = await resp.json();
    if (status) status.textContent = 'Uploading to S3...';

    // Step 2: Upload file directly to S3 using presigned URL
    const uploadResp = await fetch(uploadUrl, {
      method: 'PUT',
      headers: { 'Content-Type': file.type },
      body: file
    });

    if (!uploadResp.ok) {
      if (status) status.textContent = `S3 upload failed: ${uploadResp.status}`;
      return;
    }

    if (status) status.textContent = 'Upload complete!';

    // Clear form and reload photos
    if (fileInput) fileInput.value = '';
    if (titleInput) titleInput.value = '';
    setTimeout(() => {
      if (status) status.textContent = '';
      loadPhotos();
    }, 1000);

  } catch (e) {
    console.error('Upload error:', e);
    if (status) status.textContent = `Error: ${e.message}`;
  }
}


// ── Delete ────────────────────────────────────────────────────────────────────

async function deletePhoto(photoId) {
  if (!confirm('Delete this photo? This cannot be undone.')) return;

  try {
    const resp = await fetch(`/photos/${photoId}`, {
      method:  'DELETE',
      headers: authHeaders()
    });

    if (!resp.ok) {
      const err = await resp.json();
      alert(`Delete failed: ${err.error || resp.status}`);
      return;
    }

    // Reload photos
    await loadPhotos();

  } catch (e) {
    console.error('Delete error:', e);
    alert(`Delete error: ${e.message}`);
  }
}


// ── Toggle visibility ─────────────────────────────────────────────────────────

async function toggleVisibility(photoId, newIsPublic) {
  try {
    const resp = await fetch(`/photos/${photoId}`, {
      method:  'PATCH',
      headers: authHeaders(),
      body:    JSON.stringify({ is_public: newIsPublic })
    });

    if (!resp.ok) {
      const err = await resp.json();
      alert(`Toggle failed: ${err.error || resp.status}`);
      return;
    }

    // Reload photos to reflect change
    await loadPhotos();

  } catch (e) {
    console.error('Toggle error:', e);
    alert(`Toggle error: ${e.message}`);
  }
}


// ── Bootstrap ─────────────────────────────────────────────────────────────────

(async function init() {
  const handled = await handleCallback();
  if (handled) return;

  renderAuthButton();
  renderPremiumControls();
  await loadPhotos();
})();
