"""
photoviewer-authorizer — Week 7

Changes from Week 6:
  - Passes 'sub' (cognito:sub) in the authorizer context alongside groups.
    Lambda needs the caller's identity for ownership checks on DELETE and PATCH.

No third-party packages required. Uses only Python stdlib + boto3 (Lambda runtime).

Two jobs:
  1. Verify origin secret (required) — ensures request came from CloudFront
  2. Validate JWT (optional)         — establishes identity if Authorization header present

Environment variables required:
  COGNITO_USER_POOL_ID  e.g. us-east-1_XXXXXXXXX
  COGNITO_APP_CLIENT_ID e.g. 1abc2defg3hijklmno4pqrst

Secret in Secrets Manager:
  photoviewer/origin-verify-secret  (key: "ORIGIN_SECRET")
"""

import base64
import hashlib
import json
import os
import time
import urllib.request

import boto3

# ── Config ────────────────────────────────────────────────────────────────────

REGION        = 'us-east-1'
USER_POOL_ID  = os.environ['COGNITO_USER_POOL_ID']
APP_CLIENT_ID = os.environ['COGNITO_APP_CLIENT_ID']
SECRET_NAME   = 'photoviewer/origin-verify-secret'
JWKS_URL      = (
    f'https://cognito-idp.{REGION}.amazonaws.com'
    f'/{USER_POOL_ID}/.well-known/jwks.json'
)

# Module-level cache — reused across warm invocations
secrets_client = boto3.client('secretsmanager', region_name=REGION)
_origin_secret = None
_jwks          = None

# SHA-256 DigestInfo prefix used in PKCS#1 v1.5 signatures (RFC 3447)
_SHA256_DIGEST_INFO = bytes([
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86,
    0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05,
    0x00, 0x04, 0x20
])


# ── Helpers ───────────────────────────────────────────────────────────────────

def b64url_decode(s):
    """Decode a base64url string (with or without padding)."""
    s += '=' * (4 - len(s) % 4)
    return base64.urlsafe_b64decode(s)


def get_origin_secret():
    global _origin_secret
    if _origin_secret is None:
        resp = secrets_client.get_secret_value(SecretId=SECRET_NAME)
        _origin_secret = json.loads(resp['SecretString'])['ORIGIN_SECRET']
    return _origin_secret


def get_jwks():
    global _jwks
    if _jwks is None:
        with urllib.request.urlopen(JWKS_URL) as r:
            _jwks = json.loads(r.read())
    return _jwks


def verify_rs256(message, signature, n, e):
    """
    Verify an RS256 (PKCS#1 v1.5 + SHA-256) signature using only Python builtins.
    """
    k      = (n.bit_length() + 7) // 8
    em_int = pow(int.from_bytes(signature, 'big'), e, n)
    em     = em_int.to_bytes(k, 'big')

    if len(em) < 11 or em[0] != 0x00 or em[1] != 0x01:
        raise ValueError('Invalid PKCS#1 v1.5 padding')

    i = 2
    while i < len(em) and em[i] == 0xFF:
        i += 1

    if i == 2 or i >= len(em) or em[i] != 0x00:
        raise ValueError('Invalid PKCS#1 v1.5 padding structure')

    body     = em[i + 1:]
    expected = _SHA256_DIGEST_INFO + hashlib.sha256(message).digest()

    if body != expected:
        raise ValueError('Signature verification failed')


# ── JWT validation ────────────────────────────────────────────────────────────

def validate_jwt(token):
    """
    Verify a Cognito JWT and return (sub, groups).
    Raises on any validation failure.

    Week 7 change: returns sub alongside groups so Lambda can check ownership.
    """
    parts = token.split('.')
    if len(parts) != 3:
        raise ValueError('Malformed JWT')

    header_b64, payload_b64, sig_b64 = parts

    header  = json.loads(b64url_decode(header_b64))
    payload = json.loads(b64url_decode(payload_b64))

    # Algorithm check
    if header.get('alg') != 'RS256':
        raise ValueError(f"Unexpected algorithm: {header.get('alg')}")

    # Find matching public key by kid
    kid  = header.get('kid')
    jwks = get_jwks()
    key  = next((k for k in jwks['keys'] if k['kid'] == kid), None)
    if key is None:
        raise ValueError(f'No matching public key for kid: {kid}')

    # Extract RSA public key components from JWK
    n = int.from_bytes(b64url_decode(key['n']), 'big')
    e = int.from_bytes(b64url_decode(key['e']), 'big')

    # Verify RS256 signature
    message   = f'{header_b64}.{payload_b64}'.encode()
    signature = b64url_decode(sig_b64)
    verify_rs256(message, signature, n, e)

    # Verify expiry
    if time.time() > payload.get('exp', 0):
        raise ValueError('Token has expired')

    # Verify audience
    if payload.get('aud') != APP_CLIENT_ID:
        raise ValueError('Token audience does not match app client ID')

    # Only accept ID tokens
    if payload.get('token_use') != 'id':
        raise ValueError('Token is not an ID token')

    sub    = payload.get('sub', '')
    groups = payload.get('cognito:groups', [])
    return sub, groups


# ── Handler ───────────────────────────────────────────────────────────────────

def lambda_handler(event, context):
    headers = event.get('headers', {}) or {}

    # Step 1 — origin secret (required)
    if headers.get('x-origin-verify', '') != get_origin_secret():
        print('REJECT: origin secret missing or incorrect')
        return {'isAuthorized': False}

    # Step 2 — JWT (optional)
    sub         = ''
    groups      = []
    auth_header = headers.get('authorization', '')

    if auth_header.startswith('Bearer '):
        token = auth_header[7:]
        try:
            sub, groups = validate_jwt(token)
            print(f'AUTH: sub={sub} groups={groups}')
        except Exception as e:
            print(f'REJECT: JWT validation failed — {e}')
            return {'isAuthorized': False}
    else:
        print('UNAUTH: no JWT present')

    return {
        'isAuthorized': True,
        'context': {
            'sub': sub,
            'groups': json.dumps(groups)
        }
    }
