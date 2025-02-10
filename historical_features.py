
import boto3
import pandas as pd
import time
import json
from botocore.exceptions import ClientError
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_squared_error
import pickle

# Set AWS region and feature store parameters
AWS_REGION = "us-east-2"
ATHENA_BUCKET = "historical-cust-features-0602" 
FEATURESTORE_BUCKET = "customer-feature-store-0602"  
FEATURE_GROUP_NAME = "CustomerTransactions"
ATHENA_DATABASE = "featurestore_offline"
ATHENA_TABLE = "CustomerTransactions"


# Initialize AWS clients
s3_client = boto3.client("s3", region_name=AWS_REGION)
athena_client = boto3.client("athena", region_name=AWS_REGION)
sagemaker_client = boto3.client("sagemaker", region_name=AWS_REGION)

# 1 Run Athena query to fetch historical data
def run_athena_query():
    query = f"""
    SELECT customer_id, event_time, latest_purchase_value, latest_loyalty_score
    FROM {ATHENA_DATABASE}.{ATHENA_TABLE}
    WHERE event_time BETWEEN '2022-01-01T00:00:00Z' AND '2022-08-31T23:59:59Z';
    """
    response = athena_client.start_query_execution(
        QueryString=query,
        QueryExecutionContext={"Database": ATHENA_DATABASE},
        ResultConfiguration={"OutputLocation": f"s3://{ATHENA_BUCKET}/"},
    )
    query_execution_id = response["QueryExecutionId"]
    print(f"✅ Athena query started (QueryExecutionId: {query_execution_id})")
    return query_execution_id

# 2. Wait for query execution to complete
def wait_for_query(query_execution_id):
    while True:
        response = athena_client.get_query_execution(QueryExecutionId=query_execution_id)
        state = response["QueryExecution"]["Status"]["State"]
        if state in ["SUCCEEDED", "FAILED", "CANCELLED"]:
            break
        print("⏳ Query is still running...")
        time.sleep(5)

    if state == "SUCCEEDED":
        output_location = response["QueryExecution"]["ResultConfiguration"]["OutputLocation"]
        print(f"✅ Query completed. Results stored at: {output_location}")
        return output_location
    else:
        raise Exception(f"❌ Query failed: {response['QueryExecution']['Status']['StateChangeReason']}")

# 3 Download query results to S3
def download_and_load_results(output_location):
    filename = "historical_features.csv"
    s3_client.download_file(ATHENA_BUCKET, output_location.split("/")[-1], filename)
    print(f"✅ Results downloaded as '{filename}'")

    # Load into Pandas
    df = pd.read_csv(filename)
    df["event_time"] = pd.to_datetime(df["event_time"])
    df = df.sort_values(by="event_time")
    print(f"✅ Loaded {len(df)} historical feature records into Pandas DataFrame.")
    return df

# 4. Train ML model
def train_ml_model(df):\
  

    # Select features and target variable
    X = df[['latest_purchase_value']]
    y = df['latest_loyalty_score']  

    # Split into training and testing data
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    # Train a RandomForest model
    model = RandomForestRegressor(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)

    # Evaluate model performance
    y_pred = model.predict(X_test)
    mse = mean_squared_error(y_test, y_pred)
    print(f"✅ Model trained! Mean Squared Error: {mse}")

    return model

# 5. Save model to S3
def save_model(model):
    model_filename = "model.pkl"
    with open(model_filename, "wb") as model_file:
        pickle.dump(model, model_file)

    s3_key = "saved_models/model.pkl"
    s3_client.upload_file(model_filename, FEATURESTORE_BUCKET, s3_key)
    print(f"✅ Model uploaded to S3: s3://{FEATURESTORE_BUCKET}/{s3_key}")

# 🟢 EXECUTE ALL STEPS
query_id = run_athena_query()
query_output = wait_for_query(query_id)
df_historical = download_and_load_results(query_output)
ml_model = train_ml_model(df_historical)
save_model(ml_model)

print("🎯 Model training and saving completed!")





