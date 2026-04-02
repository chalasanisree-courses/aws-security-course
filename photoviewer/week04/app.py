import boto3
import json
from flask import Flask, jsonify
from boto3.dynamodb.conditions import Attr

app = Flask(__name__)

# DynamoDB config
REGION = 'us-east-1'
TABLE_NAME = 'photoviewer-photos'

dynamodb = boto3.resource('dynamodb', region_name=REGION)
table = dynamodb.Table(TABLE_NAME)


@app.route('/health')
def health():
    return jsonify({'status': 'ok'}), 200


@app.route('/photos')
def get_photos():
    response = table.scan(
        FilterExpression=Attr('is_public').eq(True)
    )
    photos = [
        {
            'photo_id': item['photo_id'],
            's3_key': item['s3_key']
        }
        for item in response['Items']
    ]
    return jsonify(photos), 200


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
