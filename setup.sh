#!/bin/bash

# Set AWS Region
AWS_REGION="us-east-2"

# Define IAM Role Name
IAM_ROLE_NAME="SageMakerFeatureStoreRole"
IAM_POLICY_NAME="GlueAthenaS3Access"

# Define S3 Buckets
FEATURE_STORE_BUCKET="customer-feature-store-0602"
ATHENA_OUTPUT_BUCKET="historical-cust-features-0602"

# Define Feature Store Name
FEATURE_GROUP_NAME="CustomerTransactions"

# Define Athena Database & Table
ATHENA_DATABASE="featurestore_offline"
ATHENA_TABLE="CustomerTransactions"

echo "🚀 Starting AWS Resource Setup..."

# 1 Check & Create IAM Role
ROLE_EXISTS=$(aws iam get-role --role-name $IAM_ROLE_NAME --query "Role.RoleName" --output text 2>/dev/null || echo "NO")

if [[ "$ROLE_EXISTS" == "$IAM_ROLE_NAME" ]]; then
    echo "✅ IAM Role '$IAM_ROLE_NAME' already exists. Skipping creation."
else
    echo "🔹 Creating IAM Role: $IAM_ROLE_NAME"
    aws iam create-role --role-name $IAM_ROLE_NAME --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": { "Service": "sagemaker.amazonaws.com" },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    echo "✅ IAM Role Created!"
fi

# 2️ Attach Required Policies
POLICIES=("AmazonSageMakerFullAccess" "AmazonAthenaFullAccess" "AmazonS3FullAccess" "AWSGlueConsoleFullAccess" "AmazonDynamoDBFullAccess")

for POLICY in "${POLICIES[@]}"; do
    POLICY_ARN="arn:aws:iam::aws:policy/$POLICY"
    ATTACHED=$(aws iam list-attached-role-policies --role-name $IAM_ROLE_NAME --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN'].PolicyArn" --output text)
    
    if [[ "$ATTACHED" == "$POLICY_ARN" ]]; then
        echo "✅ IAM Policy '$POLICY' is already attached."
    else
        echo "🔹 Attaching IAM Policy: $POLICY"
        aws iam attach-role-policy --role-name $IAM_ROLE_NAME --policy-arn $POLICY_ARN
    fi
done

# 3️ Check & Create S3 Buckets
BUCKETS=($FEATURE_STORE_BUCKET $ATHENA_OUTPUT_BUCKET)

for BUCKET in "${BUCKETS[@]}"; do
    if aws s3api head-bucket --bucket $BUCKET 2>/dev/null; then
        echo "✅ S3 Bucket '$BUCKET' already exists. Skipping creation."
    else
        echo "🔹 Creating S3 Bucket: $BUCKET"
        aws s3api create-bucket --bucket $BUCKET --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
    fi
done

# 4 Check & Create SageMaker Feature Store
echo "🔹 Checking if Feature Group '$FEATURE_GROUP_NAME' exists..."
FEATURE_GROUP_EXISTS=$(aws sagemaker list-feature-groups --query "FeatureGroupSummaries[?FeatureGroupName=='$FEATURE_GROUP_NAME'].FeatureGroupName" --output text)

if [[ -n "$FEATURE_GROUP_EXISTS" && "$FEATURE_GROUP_EXISTS" != "None" ]]; then
    echo "✅ Feature Store '$FEATURE_GROUP_NAME' already exists. Skipping creation."
else
    echo "🔹 Creating SageMaker Feature Store..."
    aws sagemaker create-feature-group \
        --feature-group-name $FEATURE_GROUP_NAME \
        --record-identifier-feature-name "customer_id" \
        --event-time-feature-name "event_time" \
        --feature-definitions '[{"FeatureName": "customer_id", "FeatureType": "Integral"},
                                {"FeatureName": "event_time", "FeatureType": "String"},
                                {"FeatureName": "latest_purchase_value", "FeatureType": "Fractional"},
                                {"FeatureName": "latest_loyalty_score", "FeatureType": "Fractional"}]' \
        --offline-store-config "S3StorageConfig={S3Uri=s3://$FEATURE_STORE_BUCKET/}" \
        --online-store-config "EnableOnlineStore=true" \
        --role-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/$IAM_ROLE_NAME" \
        --region $AWS_REGION

    echo "⏳ Waiting for Feature Group to be created..."
    while true; do
        STATUS=$(aws sagemaker describe-feature-group --feature-group-name $FEATURE_GROUP_NAME --query "FeatureGroupStatus" --output text)
        if [[ "$STATUS" == "Created" ]]; then
            echo "✅ Feature Store '$FEATURE_GROUP_NAME' successfully created."
            break
        elif [[ "$STATUS" == "Failed" ]]; then
            echo "❌ Error: Feature Group creation failed."
            exit 1
        else
            echo "⏳ Feature Group is still creating... Waiting..."
            sleep 10
        fi
    done
fi



# 5 Check & Create Athena Database
DATABASE_EXISTS=$(aws athena list-databases --query "DatabaseList[?Name=='$ATHENA_DATABASE'].Name" --output text)

if [[ "$DATABASE_EXISTS" == "$ATHENA_DATABASE" ]]; then
    echo "✅ Athena Database '$ATHENA_DATABASE' already exists. Skipping creation."
else
    echo "🔹 Creating Athena Database..."
    aws athena start-query-execution --query-string "CREATE DATABASE IF NOT EXISTS $ATHENA_DATABASE" \
        --result-configuration OutputLocation=s3://$ATHENA_OUTPUT_BUCKET/
    echo "✅ Athena Database Created!"
fi

# 6️ Check & Create Athena Table
TABLE_EXISTS=$(aws athena start-query-execution \
    --query-string "SHOW TABLES IN $ATHENA_DATABASE;" \
    --query-execution-context Database=$ATHENA_DATABASE \
    --result-configuration OutputLocation=s3://$ATHENA_OUTPUT_BUCKET/ \
    --output text | grep -w $ATHENA_TABLE || echo "NO")

if [[ "$TABLE_EXISTS" == "$ATHENA_TABLE" ]]; then
    echo "✅ Athena Table '$ATHENA_TABLE' already exists. Skipping creation."
else
    echo "🔹 Creating Athena Table..."
    aws athena start-query-execution --query-string "
        CREATE EXTERNAL TABLE IF NOT EXISTS $ATHENA_DATABASE.$ATHENA_TABLE (
            customer_id INT,
            event_time STRING,
            latest_purchase_value DOUBLE,
            latest_loyalty_score DOUBLE
        ) 
        STORED AS PARQUET 
        LOCATION 's3://$FEATURE_STORE_BUCKET/'
        TBLPROPERTIES ('parquet.compression'='SNAPPY');
    " --query-execution-context Database=$ATHENA_DATABASE \
        --result-configuration OutputLocation=s3://$ATHENA_OUTPUT_BUCKET/
    echo "✅ Athena Table Created!"
fi

echo "✅ AWS Resources Setup Completed!"



