import json
import boto3
import os
import uuid

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    http_method = event['httpMethod']
    path = event['path']
    
    if http_method == 'POST':
        return create_user(event)
    elif http_method == 'GET' and path == '/users':
        return list_users(event)
    elif http_method == 'GET':
        return get_user(event)
    elif http_method == 'PUT':
        return update_user(event)
    elif http_method == 'DELETE':
        return delete_user(event)
    else:
        return {
            'statusCode': 405,
            'body': json.dumps('Method not allowed')
        }

# create function
def create_user(event):
    # Step 1: extract and parse the body (like JSON.parse() in JavaScript)
    body = json.loads(event['body'])
    
    # Step 2: generate a unique userId
    user_id = str(uuid.uuid4())
    
    # Step 3: build the user item (like a Java HashMap or JS object)
    item = {
        'userId': user_id,
        'UserName': body['UserName'],
        'UserSurname': body['UserSurname'],
        'UserBirthdate': body['UserBirthdate'],
        'UserSex': body['UserSex'],
        'UserPost': body['UserPost'],
        'UserInVacation': body['UserInVacation']
    }
    
    # Step 4: save to DynamoDB
    table.put_item(Item=item)
    
    # Step 5: return success response
    return {
        'statusCode': 201,
        'body': json.dumps({'message': 'User created', 'userId': user_id})
    }

#get user function
def get_user(event):
    
    # Step 1: get the userId from the URL
    user_id = event['pathParameters']['userId']
    
    # Step 2: look for the user in DynamoDB
    response = table.get_item(Key={'userId': user_id})
    item = response.get('Item')  # returns None if not found
    
    # Step 3: return response
    if item:
        return {
            'statusCode': 200,
            'body': json.dumps({
                'userId': user_id,
                'UserName': item['UserName'],
                'UserSurname': item['UserSurname'],
                'UserBirthdate': item['UserBirthdate'],
                'UserSex': item['UserSex'],
                'UserPost': item['UserPost'],
                'UserInVacation': item['UserInVacation']
            })
        }
    else:
        return {
            'statusCode': 404,
            'body': json.dumps({'message': 'User not found'})
        }

#user list
def list_users(event):
    
    # Step 1: get query parameters for filtering (optional)
    query_params = event.get('queryStringParameters') or {}
    
    # Step 2: get all users from DynamoDB
    response = table.scan()
    items = response.get('Items')  # returns empty list if none found
    
    # Step 3: filter by name if provided
    if query_params.get('name'):
        items = [i for i in items if i.get('UserName') == query_params['name']]
    
    # Step 4: return response
    if items:
        return {
            'statusCode': 200,
            'body': json.dumps(items)
        }
    else:
        return {
            'statusCode': 404,
            'body': json.dumps({'message': 'No users found'})
        }

#update user
def update_user(event):
    
    # Step 1: get the userId from the URL
    user_id = event['pathParameters']['userId']
    
    # Step 2: check if user exists
    response = table.get_item(Key={'userId': user_id})
    item = response.get('Item')
    
    if item:
        # Step 3: parse the body
        body = json.loads(event['body'])
        
        # Step 4: update the item in DynamoDB
        table.update_item(
            Key={'userId': user_id},
            UpdateExpression='SET UserName=:n, UserSurname=:s, UserBirthdate=:b, UserSex=:sx, UserPost=:p, UserInVacation=:v',
            ExpressionAttributeValues={
                ':n': body['UserName'],
                ':s': body['UserSurname'],
                ':b': body['UserBirthdate'],
                ':sx': body['UserSex'],
                ':p': body['UserPost'],
                ':v': body['UserInVacation']
            }
        )
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'User updated'})
        }
    else:
        return {
            'statusCode': 404,
            'body': json.dumps({'message': 'User not found'})
        }

#delete user
def delete_user(event):
    
    # Step 1: get the userId from the URL
    user_id = event['pathParameters']['userId']
    
    # Step 2: check if user exists
    response = table.get_item(Key={'userId': user_id})
    item = response.get('Item')
    
    if item:
        # Step 3: delete the user
        table.delete_item(Key={'userId': user_id})
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'User deleted'})
        }
    else:
        return {
            'statusCode': 404,
            'body': json.dumps({'message': 'User not found'})
        }
