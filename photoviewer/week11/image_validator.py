"""
PhotoViewer Image Validator — Week 11
Validates uploaded files are real images using Pillow.
Triggered by S3 event notification on the photos/ prefix.

Deliberately uses Pillow 9.5.0 (has known CVEs including
CVE-2023-50447) so Inspector has something to find.
"""

import json
import boto3
from PIL import Image
import io

s3 = boto3.client('s3')


def lambda_handler(event, context):
    # Extract bucket and key from the S3 event
    record = event['Records'][0]
    bucket = record['s3']['bucket']['name']
    key = record['s3']['object']['key']

    print(f'Validating: s3://{bucket}/{key}')

    try:
        # Download the object
        response = s3.get_object(Bucket=bucket, Key=key)
        body = response['Body'].read()

        # Attempt to open as an image
        img = Image.open(io.BytesIO(body))
        img.verify()  # Verify it's a valid image

        # Re-open to get dimensions (verify() closes the image)
        img = Image.open(io.BytesIO(body))
        width, height = img.size
        fmt = img.format or 'UNKNOWN'

        # Tag as PASSED with image metadata
        tags = {
            'validation': 'PASSED',
            'image-format': fmt,
            'image-width': str(width),
            'image-height': str(height)
        }

        print(f'PASSED: {key} ({fmt} {width}x{height})')

    except Exception as e:
        # Not a valid image — tag as CAUTION
        tags = {
            'validation': 'CAUTION',
            'validation-error': str(e)[:200]
        }

        print(f'CAUTION: {key} — {e}')

    # Apply tags to the S3 object
    tag_set = [{'Key': k, 'Value': v} for k, v in tags.items()]
    s3.put_object_tagging(
        Bucket=bucket,
        Key=key,
        Tagging={'TagSet': tag_set}
    )

    return {
        'statusCode': 200,
        'body': json.dumps({
            'bucket': bucket,
            'key': key,
            'validation': tags['validation']
        })
    }
