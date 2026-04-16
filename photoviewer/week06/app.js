/**
 * Photo Viewer — app.js (Week 6)
 *
 * Changes from Week 5:
 *   - Login / Logout button in the top-right corner
 *   - On login: redirect to Cognito Hosted UI
 *   - On callback: exchange auth code for JWT, store in sessionStorage
 *   - On every /photos fetch: include Authorization: Bearer <token> if present
 *   - JWT expiry: silent reload clears state and returns to unauthenticated view
 *   - On logout: clear sessionStorage, redirect to Cognito /logout endpoint
 *
 * BEFORE DEPLOYING — replace these three placeholders:
 *   YOUR_COGNITO_DOMAIN    e.g. photoviewer-644094189785
 *   YOUR_APP_CLIENT_ID     e.g. 1abc2defg3hijklmno4pqrst
 *   YOUR_CLOUDFRONT_DOMAIN e.g. d1kbm2nphud61r.cloudfront.net
 */

// ── Configuration ─────────────────────────────────────────────────────────────

const COGNITO_DOMAIN    = 'YOUR_COGNITO_DOMAIN';
const APP_CLIENT_ID     = 'YOUR_APP_CLIENT_ID';
const CLOUDFRONT_DOMAIN = 'YOUR_CLOUDFRONT_DOMAIN';

const COGNITO_BASE      = `https://${COGNITO_DOMAIN}.auth.us-east-1.amazoncognito.com`;
const REDIRECT_URI      = `https://${CLOUDFRONT_DOMAIN}/callback`;
const LOGOUT_URI        = `https://${CLOUDFRONT_DOMAIN}`;
const TOKEN_KEY         = 'pv_id_token';


// ── Token helpers ─────────────────────────────────────────────────────────────

function getToken() {
  return sessionStorage.getItem(TOKEN_KEY);
}

function clearToken() {
  sessionStorage.removeItem(TOKEN_KEY);
}

function isTokenExpired(token) {
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return Date.now() >= payload.exp * 1000;
  } catch {
    return true;
  }
}

function getUserEmail(token) {
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return payload.email || null;
  } catch {
    return null;
  }
}


// ── Auth flow ─────────────────────────────────────────────────────────────────

function login() {
  const url = new URL(`${COGNITO_BASE}/oauth2/authorize`);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('client_id',     APP_CLIENT_ID);
  url.searchParams.set('redirect_uri',  REDIRECT_URI);
  url.searchParams.set('scope',         'openid email profile');
  window.location.href = url.toString();
}

function logout() {
  clearToken();
  const url = new URL(`${COGNITO_BASE}/logout`);
  url.searchParams.set('client_id',   APP_CLIENT_ID);
  url.searchParams.set('logout_uri',  LOGOUT_URI);
  window.location.href = url.toString();
}

async function exchangeCodeForToken(code) {
  const body = new URLSearchParams({
    grant_type:   'authorization_code',
    client_id:    APP_CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    code:         code
  });

  const response = await fetch(`${COGNITO_BASE}/oauth2/token`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    body.toString()
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Token exchange failed: ${err}`);
  }

  const data = await response.json();
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

  // Clean the URL and reload so the page renders without the code in the address bar
  window.history.replaceState({}, document.title, '/');
  window.location.reload();
  return true;
}


// ── UI ────────────────────────────────────────────────────────────────────────

function renderAuthButton() {
  const token = getToken();
  const btn   = document.getElementById('auth-btn');
  const label = document.getElementById('auth-btn-label');
  if (!btn || !label) return;

  if (token && !isTokenExpired(token)) {
    const email = getUserEmail(token);
    label.textContent = email ? `Sign out (${email})` : 'Sign out';
    btn.onclick = logout;
  } else {
    label.textContent = 'Sign in with Google';
    btn.onclick = login;
  }
}


// ── Photos ────────────────────────────────────────────────────────────────────

async function loadPhotos() {
  const token   = getToken();
  const headers = {};

  // If token exists but has expired, clear it and reload silently
  if (token && isTokenExpired(token)) {
    clearToken();
    window.location.reload();
    return;
  }

  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const response = await fetch('/photos', { headers });
  if (!response.ok) {
    console.error('Failed to load photos:', response.status);
    return;
  }

  const photos  = await response.json();
  const gallery = document.getElementById('gallery');
  if (!gallery) return;

  gallery.innerHTML = '';
  photos.forEach(photo => {
    const img       = document.createElement('img');
    img.src         = `/photos/${photo.s3_key}`;
    img.alt         = photo.photo_id;
    img.className   = 'photo-thumb';
    gallery.appendChild(img);
  });
}


// ── Bootstrap ─────────────────────────────────────────────────────────────────

(async function init() {
  // Handle Cognito callback — if a code is in the URL, exchange it and reload
  const handled = await handleCallback();
  if (handled) return;

  renderAuthButton();
  await loadPhotos();
})();
