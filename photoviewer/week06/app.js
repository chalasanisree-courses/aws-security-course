/**
 * Photo Viewer — app.js (Week 6)
 *
 * Changes from Week 5:
 *   - Login / Logout button in the top-right corner
 *   - On login: redirect to Cognito Hosted UI with PKCE
 *   - On callback: exchange auth code + code_verifier for JWT, store in sessionStorage
 *   - On every /photos fetch: include Authorization: Bearer <token> if present
 *   - JWT expiry: silent reload clears state and returns to unauthenticated view
 *   - On logout: clear sessionStorage, redirect to Cognito /logout endpoint
 *   - On sign-in: Google "G" icon replaced with user's initial from JWT email claim
 *
 * PKCE (Proof Key for Code Exchange):
 *   Before redirecting to Cognito, app.js generates a random code_verifier,
 *   hashes it to a code_challenge, and sends the challenge with the login request.
 *   When exchanging the auth code for a token, app.js sends the original
 *   code_verifier. Cognito hashes it and checks it matches. An attacker who
 *   intercepts the auth code from the URL cannot exchange it — they don't have
 *   the code_verifier that only this browser session generated.
 *
 * BEFORE DEPLOYING — replace these three placeholders:
 *   YOUR_COGNITO_DOMAIN    e.g. photoviewer-web-client-a1b2c3d4
 *   YOUR_APP_CLIENT_ID     e.g. 1abc2defg3hijklmno4pqrst
 *   YOUR_CLOUDFRONT_DOMAIN e.g. dXXXXXXXXXXXXX.cloudfront.net
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
  // 43-128 chars of URL-safe random bytes — spec requirement
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

function getUserEmail(token) {
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return payload.email || null;
  } catch {
    return null;
  }
}


// ── Auth flow ─────────────────────────────────────────────────────────────────

async function login() {
  const verifier   = generateCodeVerifier();
  const challenge  = await generateCodeChallenge(verifier);

  // Store verifier — must survive the redirect and be retrievable on callback
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
  if (!verifier) throw new Error('No code_verifier found — possible replay attack or session cleared');

  const body = new URLSearchParams({
    grant_type:    'authorization_code',
    client_id:     APP_CLIENT_ID,
    redirect_uri:  REDIRECT_URI,
    code:          code,
    code_verifier: verifier       // Cognito hashes this and checks against the challenge
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

  // Clean the ?code= from the URL and reload
  window.history.replaceState({}, document.title, '/');
  window.location.reload();
  return true;
}


// ── UI ────────────────────────────────────────────────────────────────────────

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


// ── Photos ────────────────────────────────────────────────────────────────────

async function loadPhotos() {
  const token   = getToken();
  const headers = {};

  // If token exists but has expired, clear and reload silently
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
  const img     = document.getElementById('photo');
  const counter = document.getElementById('counter');
  if (!img) return;

  // Keep existing photo cycling logic compatible
  window._photos       = photos;
  window._currentIndex = Math.floor(Math.random() * photos.length);
  showPhoto(window._currentIndex);
}

function showPhoto(index) {
  const photos  = window._photos || [];
  const img     = document.getElementById('photo');
  const counter = document.getElementById('counter');
  if (!img || photos.length === 0) return;
  img.src         = '/' + photos[index].s3_key;
  img.alt         = photos[index].photo_id;
  counter.textContent = (index + 1) + ' of ' + photos.length;
}

function nextPhoto() {
  const photos = window._photos || [];
  if (photos.length === 0) return;
  window._currentIndex = (window._currentIndex + 1) % photos.length;
  showPhoto(window._currentIndex);
}


// ── Bootstrap ─────────────────────────────────────────────────────────────────

(async function init() {
  const handled = await handleCallback();
  if (handled) return;

  renderAuthButton();
  await loadPhotos();
})();
