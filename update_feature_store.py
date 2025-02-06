
import boto3
import pandas as pd
import time
from datetime import datetime, timezone


# Load dataset
file_path = "test_task_data.csv"  
df = pd.read_csv(file_path)

df.head(3)


# Convert purchase_timestamp to datetime format
df["purchase_timestamp"] = pd.to_datetime(df["purchase_timestamp"])

# Sort records in chronological order to simulate real-time streaming
df = df.sort_values(by="purchase_timestamp", ascending=True)

# Initialize SageMaker Feature Store client
sm_client = boto3.client("sagemaker-featurestore-runtime", region_name="us-east-2")

feature_group_name = "CustomerTransactions"

# Dictionary to store the latest record for each customer
latest_customer_records = {}


# Function to send records to Feature Store
def update_feature_store(row):
    customer_id = row["customer_id"]
    timestamp = row["purchase_timestamp"]
    
    # Format event_time in ISO 8601 format (required by SageMaker Feature Store)
    event_time = timestamp.replace(tzinfo=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Ensure only the latest record for each customer is updated
    latest_customer_records[customer_id] = {
        "FeatureGroupName": feature_group_name,
        "Record": [
            {"FeatureName": "customer_id", "ValueAsString": str(customer_id)},
            {"FeatureName": "event_time", "ValueAsString": event_time},
            {"FeatureName": "latest_purchase_value", "ValueAsString": str(row["purchase_value"])},
            {"FeatureName": "latest_loyalty_score", "ValueAsString": str(row["loyalty_score"])}
        ]
    }

    try:
        response = sm_client.put_record(**latest_customer_records[customer_id])
        print(f"✅ Successfully updated feature store for Customer ID: {customer_id}")
    except Exception as e:
        print(f"❌ Error updating feature store for Customer ID {customer_id}: {e}")

# Stream records one by one to simulate real-time updates
for _, row in df.iterrows():
    update_feature_store(row)
    time.sleep(1)  # Simulating delay for real-time data ingestion

print("🎯 Feature Store Update Completed!")


#Function to fetch the latest features given a customer_id

def get_latest_features(customer_id):
    response = sm_client.get_record(
        FeatureGroupName=feature_group_name,
        RecordIdentifierValueAsString=str(customer_id)
    )
    
    features = {feature['FeatureName']: feature['ValueAsString'] for feature in response.get('Record', [])}
    
    return features

# Example: Fetch latest features
customer_id = 29
latest_features = get_latest_features(customer_id)

latest_purchase_value = float(latest_features.get("latest_purchase_value", 0.0))
latest_loyalty_score = float(latest_features.get("latest_loyalty_score", 0.0))

print("Latest features for customer_id :29")
print(f"Latest Purchase Value: {latest_purchase_value}")
print(f"Latest Loyalty Score: {latest_loyalty_score}")





