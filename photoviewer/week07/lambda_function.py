"""
photoviewer-lambda — Week 7

Changes from Week 6:
  - Four routes: GET /photos, POST /photos, DELETE /photos/{photoId}, PATCH /photos/{photoId}
  - GET: generates presigned GET URLs for all photos (pre-seeded and uploaded)
  - POST: premium-only, creates DynamoDB record + presigned PUT URL with conditions
  - DELETE: premium + owner-only, deletes S3 object + DynamoDB record
  - PATCH: premium + owner-only, updates is_public in DynamoDB
  - Reads 'sub' from authorizer context for ownership checks

Environment variables:
  PHOTO_BUCKET  e.g. photoviewer-9876543210

DynamoDB table: photoviewer-photos
Partition key:  photo_id (String)
Attributes:     s3_key, is_public, owner, uploaded_at, title
"""

import json
import os
import time
import uuid

import boto3
from boto3.dynamodb.conditions import Attr

# ── AWS clients ───────────────────────────────────────────────────────────────

REGION = 'us-east-1'
BUCKET = os.environ['PHOTO_BUCKET']

dynamodb = boto3.resource('dynamodb', region_name=REGION)
table    = dynamodb.Table('photoviewer-photos')
s3       = boto3.client('s3', region_name=REGION)

# Presigned URL TTLs
PUT_TTL = 900   # 15 minutes for uploads
GET_TTL = 300   # 5 minutes for viewing


# ── Helpers ───────────────────────────────────────────────────────────────────

def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body, default=str)
    }


def get_authorizer_context(event):
    """Extract sub and groups from the Lambda authorizer context."""
    try:
        ctx = (
            event
            .get('requestContext', {})
            .get('authorizer', {})
            .get('lambda', {})
        )
        sub    = ctx.get('sub', '')
        groups = json.loads(ctx.get('groups', '[]'))
        return sub, groups
    except (json.JSONDecodeError, AttributeError):
        return '', []


def require_premium(groups):
    """Return True if user is in the premium group."""
    return 'premium' in groups


def generate_get_url(s3_key):
    """Generate a presigned GET URL for an uploaded photo."""
    return s3.generate_presigned_url(
        'get_object',
        Params={'Bucket': BUCKET, 'Key': s3_key},
        ExpiresIn=GET_TTL
    )


# ── Route handlers ────────────────────────────────────────────────────────────

def handle_get_photos(event, sub, groups):
    """
    GET /photos — return photo list.
    Unauthenticated: is_public = true only.
    Any authenticated user: all photos.
    All photos get a presigned GET URL — no permanent CloudFront URLs.
    """
    if groups:
        print(f'Authenticated: sub={sub} groups={groups} — returning all photos')
        result = table.scan()
    else:
        print('Unauthenticated — returning public photos only')
        result = table.scan(
            FilterExpression=Attr('is_public').eq(True)
        )

    photos = result.get('Items', [])

    # Add presigned GET URL for every photo
    for photo in photos:
        s3_key = photo.get('s3_key', '')
        photo['url'] = generate_get_url(s3_key)

    return response(200, photos)


def handle_post_photos(event, sub, groups):
    """
    POST /photos — premium only.
    Creates DynamoDB record and returns a presigned PUT URL with conditions.
    """
    if not require_premium(groups):
        print(f'REJECT: POST /photos — user {sub} not in premium group')
        return response(403, {'error': 'Premium group membership required'})

    # Parse request body
    try:
        body = json.loads(event.get('body', '{}'))
    except json.JSONDecodeError:
        return response(400, {'error': 'Invalid JSON body'})

    title     = body.get('title', 'Untitled')
    is_public = body.get('is_public', True)
    content_type = body.get('content_type', 'image/jpeg')

    # Validate content type
    allowed_types = {'image/jpeg': '.jpg', 'image/png': '.png'}
    if content_type not in allowed_types:
        return response(400, {'error': f'Unsupported content type: {content_type}. Allowed: image/jpeg, image/png'})

    ext = allowed_types[content_type]

    # Generate IDs and S3 key
    photo_id = f'photo_{uuid.uuid4().hex[:12]}'
    s3_key   = f'uploads/{sub}/{photo_id}{ext}'

    # Write metadata to DynamoDB
    table.put_item(Item={
        'photo_id':    photo_id,
        'title':       title,
        'is_public':   is_public,
        'owner':       sub,
        's3_key':      s3_key,
        'uploaded_at': int(time.time())
    })

    # Generate presigned PUT URL with conditions
    presigned_url = s3.generate_presigned_url(
        'put_object',
        Params={
            'Bucket':      BUCKET,
            'Key':         s3_key,
            'ContentType': content_type
        },
        ExpiresIn=PUT_TTL
    )

    print(f'POST /photos: photo_id={photo_id} owner={sub} s3_key={s3_key}')

    return response(200, {
        'photoId':   photo_id,
        'uploadUrl': presigned_url,
        's3Key':     s3_key
    })


def handle_delete_photo(event, sub, groups):
    """
    DELETE /photos/{photoId} — premium + owner only.
    Deletes S3 object and DynamoDB record.
    """
    if not require_premium(groups):
        print(f'REJECT: DELETE — user {sub} not in premium group')
        return response(403, {'error': 'Premium group membership required'})

    photo_id = event.get('pathParameters', {}).get('photoId', '')
    if not photo_id:
        return response(400, {'error': 'Missing photoId'})

    # Fetch the item to check ownership
    result = table.get_item(Key={'photo_id': photo_id})
    item   = result.get('Item')

    if not item:
        return response(404, {'error': 'Photo not found'})

    if item.get('owner') != sub:
        print(f'REJECT: DELETE — user {sub} does not own photo {photo_id} (owner: {item.get("owner")})')
        return response(403, {'error': 'You can only delete your own photos'})

    # Delete S3 object
    s3_key = item.get('s3_key', '')
    if s3_key.startswith('uploads/'):
        s3.delete_object(Bucket=BUCKET, Key=s3_key)
        print(f'Deleted S3 object: {s3_key}')

    # Delete DynamoDB record
    table.delete_item(Key={'photo_id': photo_id})
    print(f'DELETE /photos/{photo_id}: owner={sub} s3_key={s3_key}')

    return response(200, {'deleted': photo_id})


def handle_patch_photo(event, sub, groups):
    """
    PATCH /photos/{photoId} — premium + owner only.
    Updates is_public in DynamoDB.
    """
    if not require_premium(groups):
        print(f'REJECT: PATCH — user {sub} not in premium group')
        return response(403, {'error': 'Premium group membership required'})

    photo_id = event.get('pathParameters', {}).get('photoId', '')
    if not photo_id:
        return response(400, {'error': 'Missing photoId'})

    # Parse request body
    try:
        body = json.loads(event.get('body', '{}'))
    except json.JSONDecodeError:
        return response(400, {'error': 'Invalid JSON body'})

    if 'is_public' not in body:
        return response(400, {'error': 'Missing is_public field'})

    new_is_public = bool(body['is_public'])

    # Fetch the item to check ownership
    result = table.get_item(Key={'photo_id': photo_id})
    item   = result.get('Item')

    if not item:
        return response(404, {'error': 'Photo not found'})

    if item.get('owner') != sub:
        print(f'REJECT: PATCH — user {sub} does not own photo {photo_id} (owner: {item.get("owner")})')
        return response(403, {'error': 'You can only edit your own photos'})

    # Update is_public
    table.update_item(
        Key={'photo_id': photo_id},
        UpdateExpression='SET is_public = :val',
        ExpressionAttributeValues={':val': new_is_public}
    )

    print(f'PATCH /photos/{photo_id}: is_public={new_is_public} owner={sub}')

    return response(200, {'photoId': photo_id, 'is_public': new_is_public})


# ── Router ────────────────────────────────────────────────────────────────────

def lambda_handler(event, context):
    sub, groups = get_authorizer_context(event)
    route_key   = event.get('routeKey', '')

    print(f'Route: {route_key} | sub={sub} | groups={groups}')

    if route_key == 'GET /photos':
        return handle_get_photos(event, sub, groups)

    elif route_key == 'POST /photos':
        return handle_post_photos(event, sub, groups)

    elif route_key == 'DELETE /photos/{photoId}':
        return handle_delete_photo(event, sub, groups)

    elif route_key == 'PATCH /photos/{photoId}':
        return handle_patch_photo(event, sub, groups)

    else:
        print(f'Unknown route: {route_key}')
        return response(404, {'error': f'Unknown route: {route_key}'})
