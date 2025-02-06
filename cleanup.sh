#!/bin/bash

# Set AWS Region
AWS_REGION="us-east-2"

# Define IAM Role Name
IAM_ROLE_NAME="SageMakerFeatureStoreRole"

# Define S3 Buckets
FEATURE_STORE_BUCKET="customer-feature-store-0602"
ATHENA_OUTPUT_BUCKET="historical-cust-features-0602"

# Define Feature Store Name
FEATURE_GROUP_NAME="CustomerTransactions"

# Define Athena Database & Table
ATHENA_DATABASE="featurestore_offline"
ATHENA_TABLE="CustomerTransactions"

echo "🚀 Starting AWS Resource Cleanup..."

# 1️⃣ Delete SageMaker Feature Store
echo "🔹 Checking if SageMaker Feature Group '$FEATURE_GROUP_NAME' exists..."
FEATURE_GROUP_EXISTS=$(aws sagemaker list-feature-groups --query "FeatureGroupSummaries[?FeatureGroupName=='$FEATURE_GROUP_NAME'].FeatureGroupName" --output text)

if [[ "$FEATURE_GROUP_EXISTS" == "$FEATURE_GROUP_NAME" ]]; then
    echo "🗑️ Deleting SageMaker Feature Group: $FEATURE_GROUP_NAME"
    aws sagemaker delete-feature-group --feature-group-name $FEATURE_GROUP_NAME --region $AWS_REGION
else
    echo "✅ SageMaker Feature Group '$FEATURE_GROUP_NAME' does not exist. Skipping."
fi

# 2️⃣ Delete Athena Table
echo "🔹 Checking if Athena Table '$ATHENA_TABLE' exists..."
TABLE_EXISTS=$(aws athena start-query-execution \
    --query-string "SHOW TABLES IN $ATHENA_DATABASE;" \
    --query-execution-context Database=$ATHENA_DATABASE \
    --result-configuration OutputLocation=s3://$ATHENA_OUTPUT_BUCKET/ \
    --output text | grep -w $ATHENA_TABLE || echo "NO")

if [[ "$TABLE_EXISTS" == "$ATHENA_TABLE" ]]; then
    echo "🗑️ Dropping Athena Table: $ATHENA_DATABASE.$ATHENA_TABLE"
    aws athena start-query-execution \
        --query-string "DROP TABLE IF EXISTS $ATHENA_DATABASE.$ATHENA_TABLE;" \
        --query-execution-context Database=$ATHENA_DATABASE \
        --result-configuration OutputLocation=s3://$ATHENA_OUTPUT_BUCKET/
else
    echo "✅ Athena Table '$ATHENA_TABLE' does not exist. Skipping."
fi

# 3️⃣ Delete Athena Database
echo "🔹 Checking if Athena Database '$ATHENA_DATABASE' exists..."
DATABASE_EXISTS=$(aws athena list-databases --query "DatabaseList[?Name=='$ATHENA_DATABASE'].Name" --output text)

if [[ "$DATABASE_EXISTS" == "$ATHENA_DATABASE" ]]; then
    echo "🗑️ Dropping Athena Database: $ATHENA_DATABASE"
    aws athena start-query-execution \
        --query-string "DROP DATABASE IF EXISTS $ATHENA_DATABASE;" \
        --query-execution-context Database=$ATHENA_DATABASE \
        --result-configuration OutputLocation=s3://$ATHENA_OUTPUT_BUCKET/
else
    echo "✅ Athena Database '$ATHENA_DATABASE' does not exist. Skipping."
fi

# 4️⃣ Empty and Delete S3 Buckets
BUCKETS=($FEATURE_STORE_BUCKET $ATHENA_OUTPUT_BUCKET)

for BUCKET in "${BUCKETS[@]}"; do
    echo "🔹 Checking if S3 Bucket '$BUCKET' exists..."
    if aws s3api head-bucket --bucket $BUCKET 2>/dev/null; then
        echo "🗑️ Emptying and Deleting S3 Bucket: $BUCKET"
        aws s3 rm s3://$BUCKET --recursive
        aws s3 rb s3://$BUCKET --force
    else
        echo "✅ S3 Bucket '$BUCKET' does not exist. Skipping."
    fi
done

# 5️⃣ Delete IAM Policies & Role
echo "🔹 Checking if IAM Role '$IAM_ROLE_NAME' exists..."
ROLE_EXISTS=$(aws iam get-role --role-name $IAM_ROLE_NAME --query "Role.RoleName" --output text 2>/dev/null || echo "NO")

if [[ "$ROLE_EXISTS" == "$IAM_ROLE_NAME" ]]; then
    echo "🗑️ Deleting IAM Role: $IAM_ROLE_NAME"
    aws iam detach-role-policy --role-name $IAM_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess
    aws iam detach-role-policy --role-name $IAM_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonAthenaFullAccess
    aws iam detach-role-policy --role-name $IAM_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
    aws iam detach-role-policy --role-name $IAM_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess
    aws iam detach-role-policy --role-name $IAM_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
    aws iam delete-role --role-name $IAM_ROLE_NAME
else
    echo "✅ IAM Role '$IAM_ROLE_NAME' does not exist. Skipping."
fi

echo "✅ AWS Resources Cleanup Completed!"
