import json
import boto3
from boto3.dynamodb.conditions import Attr

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
table = dynamodb.Table('photoviewer-photos')

def lambda_handler(event, context):
    print(f"DEBUG event: {json.dumps(event)}")
    try:
        response = table.scan(
            FilterExpression=Attr('is_public').eq(True)
        )
        photos = [
            {
                'photo_id': item['photo_id'],
                's3_key': item['s3_key']
            }
            for item in response.get('Items', [])
        ]
        result = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(photos)
        }
        print(f"DEBUG response: {json.dumps(result)}")
        return result
    except Exception as e:
        print(f"ERROR: {e}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }
