#!/bin/bash

# ===========================================
# Serverless User Manager API - Deploy Script
# ===========================================
# Replace these variables before running:
ACCOUNT_ID="YOUR_ACCOUNT_ID"
REGION="eu-central-1"
TABLE_NAME="Users"
FUNCTION_NAME="user-api-function"
API_NAME="user-api"
ROLE_NAME="lambda-user-api-role"
SNS_TOPIC_NAME="user-api-alerts"
ALERT_EMAIL="YOUR_EMAIL@gmail.com"

echo "============================================"
echo " Serverless User Manager API - Deployment"
echo "============================================"

# -------------------------
# Phase 1: IAM
# -------------------------
echo ""
echo "[1/5] Setting up IAM role..."

aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://trust-policy.json \
  --description "Execution role for User Manager Lambda"

aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name crud-policy \
  --policy-document file://dynamodb-policy.json

echo "IAM role created and policies attached."

# -------------------------
# Phase 2: DynamoDB
# -------------------------
echo ""
echo "[2/5] Creating DynamoDB table..."

aws dynamodb create-table \
  --table-name $TABLE_NAME \
  --attribute-definitions AttributeName=userId,AttributeType=S \
  --key-schema AttributeName=userId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

echo "Waiting for table to become active..."
aws dynamodb wait table-exists --table-name $TABLE_NAME
echo "DynamoDB table created."

# -------------------------
# Phase 3: Lambda
# -------------------------
echo ""
echo "[3/5] Deploying Lambda function..."

cd ../src
zip lambda_function.zip lambda_function.py
cd ../deployment

aws lambda create-function \
  --function-name $FUNCTION_NAME \
  --runtime python3.12 \
  --role arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://../src/lambda_function.zip \
  --environment Variables={TABLE_NAME=$TABLE_NAME}

echo "Waiting for Lambda function to become active..."
aws lambda wait function-active --function-name $FUNCTION_NAME
echo "Lambda function deployed."

# -------------------------
# Phase 4: API Gateway
# -------------------------
echo ""
echo "[4/5] Setting up API Gateway..."

API_ID=$(aws apigateway create-rest-api \
  --name $API_NAME \
  --description "User Manager REST API" \
  --endpoint-configuration types=REGIONAL \
  --query 'id' --output text)

echo "API ID: $API_ID"

ROOT_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[?path==`/`].id' --output text)

USERS_ID=$(aws apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $ROOT_ID \
  --path-part users \
  --query 'id' --output text)

USERID_ID=$(aws apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $USERS_ID \
  --path-part '{userId}' \
  --query 'id' --output text)

LAMBDA_URI="arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME/invocations"

for METHOD in POST GET; do
  aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $USERS_ID \
    --http-method $METHOD \
    --authorization-type NONE

  aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $USERS_ID \
    --http-method $METHOD \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri $LAMBDA_URI
done

for METHOD in GET PUT DELETE; do
  aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $USERID_ID \
    --http-method $METHOD \
    --authorization-type NONE

  aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $USERID_ID \
    --http-method $METHOD \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri $LAMBDA_URI
done

aws lambda add-permission \
  --function-name $FUNCTION_NAME \
  --statement-id apigateway-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*

aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name dev \
  --description "Dev stage deployment"

echo "API Gateway deployed."
echo "API URL: https://$API_ID.execute-api.$REGION.amazonaws.com/dev"

# -------------------------
# Phase 5: CloudWatch
# -------------------------
echo ""
echo "[5/5] Setting up CloudWatch alarms..."

SNS_ARN=$(aws sns create-topic \
  --name $SNS_TOPIC_NAME \
  --query 'TopicArn' --output text)

aws sns subscribe \
  --topic-arn $SNS_ARN \
  --protocol email \
  --notification-endpoint $ALERT_EMAIL

aws cloudwatch put-metric-alarm \
  --alarm-name "user-api-errors" \
  --alarm-description "Triggers when Lambda errors exceed 2 in 5 minutes" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
  --statistic Sum \
  --period 300 \
  --threshold 2 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions $SNS_ARN \
  --treat-missing-data notBreaching

aws cloudwatch put-metric-alarm \
  --alarm-name "user-api-duration" \
  --alarm-description "Triggers when latency average exceeds 1000 milliseconds" \
  --metric-name Duration \
  --namespace AWS/Lambda \
  --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
  --statistic Average \
  --period 300 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions $SNS_ARN \
  --treat-missing-data notBreaching

echo "CloudWatch alarms created."

echo ""
echo "============================================"
echo " Deployment complete!"
echo " API URL: https://$API_ID.execute-api.$REGION.amazonaws.com/dev"
echo " Check your email to confirm SNS subscription."
echo "============================================"
