"""
photoviewer-authorizer — Week 6

No third-party packages required. Uses only:
  - boto3         (Lambda runtime)
  - cryptography  (Lambda runtime)
  - urllib, json  (stdlib)

Two jobs:
  1. Verify origin secret (required) — ensures request came from CloudFront
  2. Validate JWT (optional)         — establishes identity if Authorization header present

Environment variables required:
  COGNITO_USER_POOL_ID  e.g. us-east-1_XXXXXXXXX
  COGNITO_APP_CLIENT_ID e.g. 1abc2defg3hijklmno4pqrst

Secret in Secrets Manager:
  photoviewer/origin-verify-secret  (key: "value")
"""

import base64
import json
import os
import time
import urllib.request

import boto3
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicNumbers

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


# ── Helpers ───────────────────────────────────────────────────────────────────

def b64url_decode(s):
    """Decode a base64url string (with or without padding)."""
    s += '=' * (4 - len(s) % 4)
    return base64.urlsafe_b64decode(s)


def get_origin_secret():
    global _origin_secret
    if _origin_secret is None:
        resp = secrets_client.get_secret_value(SecretId=SECRET_NAME)
        _origin_secret = json.loads(resp['SecretString'])['value']
    return _origin_secret


def get_jwks():
    global _jwks
    if _jwks is None:
        with urllib.request.urlopen(JWKS_URL) as r:
            _jwks = json.loads(r.read())
    return _jwks


# ── JWT validation ────────────────────────────────────────────────────────────

def validate_jwt(token):
    """
    Verify a Cognito JWT and return the cognito:groups claim.
    Raises on any validation failure.
    """
    parts = token.split('.')
    if len(parts) != 3:
        raise ValueError('Malformed JWT')

    header_b64, payload_b64, sig_b64 = parts

    # Decode header and payload
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

    # Construct RSA public key from JWK n and e
    n       = int.from_bytes(b64url_decode(key['n']), 'big')
    e       = int.from_bytes(b64url_decode(key['e']), 'big')
    pub_key = RSAPublicNumbers(e, n).public_key(default_backend())

    # Verify RS256 signature
    message   = f'{header_b64}.{payload_b64}'.encode()
    signature = b64url_decode(sig_b64)
    pub_key.verify(signature, message, padding.PKCS1v15(), hashes.SHA256())

    # Verify expiry
    if time.time() > payload.get('exp', 0):
        raise ValueError('Token has expired')

    # Verify audience
    if payload.get('aud') != APP_CLIENT_ID:
        raise ValueError('Token audience does not match app client ID')

    # Only accept ID tokens
    if payload.get('token_use') != 'id':
        raise ValueError('Token is not an ID token')

    return payload.get('cognito:groups', [])


# ── Handler ───────────────────────────────────────────────────────────────────

def lambda_handler(event, context):
    headers = event.get('headers', {}) or {}

    # Step 1 — origin secret (required)
    if headers.get('x-origin-verify', '') != get_origin_secret():
        print('REJECT: origin secret missing or incorrect')
        return {'isAuthorized': False}

    # Step 2 — JWT (optional)
    groups      = []
    auth_header = headers.get('authorization', '')

    if auth_header.startswith('Bearer '):
        token = auth_header[7:]
        try:
            groups = validate_jwt(token)
            print(f'AUTH: groups={groups}')
        except Exception as e:
            print(f'REJECT: JWT validation failed — {e}')
            return {'isAuthorized': False}
    else:
        print('UNAUTH: no JWT present')

    return {
        'isAuthorized': True,
        'context': {
            'groups': json.dumps(groups)
        }
    }
