import os

SECRET = os.environ['ORIGIN_SECRET']

def lambda_handler(event, context):
    print(f"DEBUG headers: {event.get('headers', {})}")
    token = event.get('headers', {}).get('x-origin-verify', '')
    print(f"DEBUG token: '{token}', SECRET: '{SECRET}'")
    return {'isAuthorized': token == SECRET}
