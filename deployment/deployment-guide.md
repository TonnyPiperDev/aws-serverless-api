# Deployment Guide

## Prerequisites
- AWS CLI installed and configured (`aws configure`)
- Python 3.12
- zip utility (`sudo apt install zip`)

---

## Phase 1: IAM

Create the Lambda execution role with a trust policy allowing Lambda to assume it.

1. Create the trust policy file `trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

2. Create the role:

```bash
aws iam create-role \
  --role-name lambda-user-api-role \
  --assume-role-policy-document file://trust-policy.json \
  --description "Execution role for User Manager Lambda"
```

3. Attach CloudWatch logging policy:

```bash
aws iam attach-role-policy \
  --role-name lambda-user-api-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
```

4. Attach DynamoDB CRUD policy:

```bash
aws iam put-role-policy \
  --role-name lambda-user-api-role \
  --policy-name crud-policy \
  --policy-document file://dynamodb-policy.json
```

---

## Phase 2: DynamoDB

Create the Users table with on-demand capacity mode.

```bash
aws dynamodb create-table \
  --table-name Users \
  --attribute-definitions AttributeName=userId,AttributeType=S \
  --key-schema AttributeName=userId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

Verify the table is active:

```bash
aws dynamodb describe-table --table-name Users
```

---

## Phase 3: Lambda

1. Zip the function:

```bash
cd src
zip lambda_function.zip lambda_function.py
```

2. Deploy the function:

```bash
aws lambda create-function \
  --function-name user-api-function \
  --runtime python3.12 \
  --role arn:aws:iam::YOUR_ACCOUNT_ID:role/lambda-user-api-role \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://lambda_function.zip \
  --environment Variables={TABLE_NAME=Users}
```

3. Verify the function is active:

```bash
aws lambda get-function --function-name user-api-function --query 'Configuration.State'
```

4. Test the function directly:

```bash
aws lambda invoke \
  --function-name user-api-function \
  --payload '{"httpMethod": "GET", "path": "/users", "queryStringParameters": null, "pathParameters": null, "body": null}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

5. To update the function after code changes:

```bash
zip lambda_function.zip lambda_function.py
aws lambda update-function-code \
  --function-name user-api-function \
  --zip-file fileb://lambda_function.zip
```

---

## Phase 4: API Gateway

1. Create the REST API:

```bash
aws apigateway create-rest-api \
  --name user-api \
  --description "User Manager REST API" \
  --endpoint-configuration types=REGIONAL
```

Save the `id` from the response as `YOUR_API_ID`.

2. Get the root resource ID:

```bash
aws apigateway get-resources --rest-api-id YOUR_API_ID
```

Save the `id` of the `/` path as `YOUR_ROOT_RESOURCE_ID`.

3. Create `/users` resource:

```bash
aws apigateway create-resource \
  --rest-api-id YOUR_API_ID \
  --parent-id YOUR_ROOT_RESOURCE_ID \
  --path-part users
```

Save the `id` as `YOUR_USERS_RESOURCE_ID`.

4. Create `/users/{userId}` resource:

```bash
aws apigateway create-resource \
  --rest-api-id YOUR_API_ID \
  --parent-id YOUR_USERS_RESOURCE_ID \
  --path-part {userId}
```

Save the `id` as `YOUR_USERID_RESOURCE_ID`.

5. Create HTTP methods (repeat for each method/resource combination):

```bash
# POST /users
aws apigateway put-method \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_USERS_RESOURCE_ID \
  --http-method POST \
  --authorization-type NONE

# GET /users
aws apigateway put-method \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_USERS_RESOURCE_ID \
  --http-method GET \
  --authorization-type NONE

# GET /users/{userId}
aws apigateway put-method \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_USERID_RESOURCE_ID \
  --http-method GET \
  --authorization-type NONE

# PUT /users/{userId}
aws apigateway put-method \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_USERID_RESOURCE_ID \
  --http-method PUT \
  --authorization-type NONE

# DELETE /users/{userId}
aws apigateway put-method \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_USERID_RESOURCE_ID \
  --http-method DELETE \
  --authorization-type NONE
```

6. Create Lambda integrations (repeat for each method/resource combination):

```bash
# POST /users
aws apigateway put-integration \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_USERS_RESOURCE_ID \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:eu-central-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-central-1:YOUR_ACCOUNT_ID:function:user-api-function/invocations

# GET /users
aws apigateway put-integration \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_USERS_RESOURCE_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:eu-central-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-central-1:YOUR_ACCOUNT_ID:function:user-api-function/invocations

# GET /users/{userId}
aws apigateway put-integration \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_USERID_RESOURCE_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:eu-central-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-central-1:YOUR_ACCOUNT_ID:function:user-api-function/invocations

# PUT /users/{userId}
aws apigateway put-integration \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_USERID_RESOURCE_ID \
  --http-method PUT \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:eu-central-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-central-1:YOUR_ACCOUNT_ID:function:user-api-function/invocations

# DELETE /users/{userId}
aws apigateway put-integration \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_USERID_RESOURCE_ID \
  --http-method DELETE \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:eu-central-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-central-1:YOUR_ACCOUNT_ID:function:user-api-function/invocations
```

7. Grant API Gateway permission to invoke Lambda:

```bash
aws lambda add-permission \
  --function-name user-api-function \
  --statement-id apigateway-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn arn:aws:execute-api:eu-central-1:YOUR_ACCOUNT_ID:YOUR_API_ID/*/*
```

8. Deploy to dev stage:

```bash
aws apigateway create-deployment \
  --rest-api-id YOUR_API_ID \
  --stage-name dev \
  --description "Dev stage deployment"
```

Your API is now live at:
```
https://YOUR_API_ID.execute-api.eu-central-1.amazonaws.com/dev
```

9. Test the API:

```bash
# Create a user
curl -X POST https://YOUR_API_ID.execute-api.eu-central-1.amazonaws.com/dev/users \
  -H "Content-Type: application/json" \
  -d '{
    "UserName": "John",
    "UserSurname": "Doe",
    "UserBirthdate": "1990-01-01",
    "UserSex": "Male",
    "UserPost": "Developer",
    "UserInVacation": false
  }'

# List all users
curl https://YOUR_API_ID.execute-api.eu-central-1.amazonaws.com/dev/users

# Get a specific user
curl https://YOUR_API_ID.execute-api.eu-central-1.amazonaws.com/dev/users/YOUR_USER_ID
```

---

## Phase 5: CloudWatch

1. Create an SNS topic for alerts:

```bash
aws sns create-topic --name user-api-alerts
```

Save the `TopicArn` from the response.

2. Subscribe your email to the topic:

```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:eu-central-1:YOUR_ACCOUNT_ID:user-api-alerts \
  --protocol email \
  --notification-endpoint YOUR_EMAIL@gmail.com
```

Check your inbox and confirm the subscription.

3. Create an error alarm (triggers when errors > 2 in 5 minutes):

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "user-api-errors" \
  --alarm-description "Triggers when Lambda errors exceed 2 in 5 minutes" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --dimensions Name=FunctionName,Value=user-api-function \
  --statistic Sum \
  --period 300 \
  --threshold 2 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:eu-central-1:YOUR_ACCOUNT_ID:user-api-alerts \
  --treat-missing-data notBreaching
```

4. Create a latency alarm (triggers when average duration > 1000ms):

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "user-api-duration" \
  --alarm-description "Triggers when latency average exceeds 1000 milliseconds" \
  --metric-name Duration \
  --namespace AWS/Lambda \
  --dimensions Name=FunctionName,Value=user-api-function \
  --statistic Average \
  --period 300 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:eu-central-1:YOUR_ACCOUNT_ID:user-api-alerts \
  --treat-missing-data notBreaching
```

5. Verify both alarms are active:

```bash
aws cloudwatch describe-alarms --query "MetricAlarms[*].{Name:AlarmName,State:StateValue}"
```
