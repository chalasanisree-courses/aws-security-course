"""
photoviewer-lambda — Week 6

Reads photos from DynamoDB. Filtering depends on identity:
  - Unauthenticated (no groups)    → is_public = true only
  - Authenticated (any group)      → all photos

The Lambda authorizer passes group context via:
  event['requestContext']['authorizer']['lambda']['groups']
  (a JSON-encoded list, e.g. '["free"]' or '["premium"]' or '[]')

DynamoDB table: photoviewer-photos
Partition key:  photo_id (String)
Attributes:     s3_key, is_public, owner, uploaded_at
"""

import json
import boto3
from boto3.dynamodb.conditions import Attr

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
table    = dynamodb.Table('photoviewer-photos')


def lambda_handler(event, context):
    # ── Read group context from authorizer ───────────────────────────────────
    try:
        authorizer_ctx = (
            event
            .get('requestContext', {})
            .get('authorizer', {})
            .get('lambda', {})
        )
        groups = json.loads(authorizer_ctx.get('groups', '[]'))
    except (json.JSONDecodeError, AttributeError):
        groups = []

    # ── Query DynamoDB ───────────────────────────────────────────────────────
    if groups:
        # Any authenticated user — return all photos
        print(f'Authenticated: groups={groups} — returning all photos')
        response = table.scan()
    else:
        # Unauthenticated — public photos only
        print('Unauthenticated — returning public photos only')
        response = table.scan(
            FilterExpression=Attr('is_public').eq(True)
        )

    photos = response.get('Items', [])

    # ── Return ───────────────────────────────────────────────────────────────
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            # '*' is acceptable here only because the Lambda authorizer requires the
            # x-origin-verify secret header (added solely by CloudFront), which blocks
            # direct cross-origin browser calls regardless of CORS. In general — and as
            # taught in Week 7 — you would scope this to your own domain.
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(photos, default=str)
    }
