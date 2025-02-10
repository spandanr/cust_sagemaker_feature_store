
import boto3
import pandas as pd
import pickle  
import json
from botocore.exceptions import NoCredentialsError

# Initialize SageMaker Feature Store Runtime client
AWS_REGION = "us-east-2"
FEATURE_GROUP_NAME = "CustomerTransactions"
sm_client = boto3.client("sagemaker-featurestore-runtime", region_name=AWS_REGION)

# 1. Retrieve Latest Features for a Given Customer ID
def get_latest_features(customer_id):
    try:
        response = sm_client.get_record(
            FeatureGroupName=FEATURE_GROUP_NAME,
            RecordIdentifierValueAsString=str(customer_id)
        )
        if "Record" not in response:
            print(f"No feature data found for Customer ID {customer_id}")
            return None

        # Convert feature list to dictionary
        features = {feature["FeatureName"]: feature["ValueAsString"] for feature in response["Record"]}
        print(f"Retrieved latest features for Customer {customer_id}: {features}")

        return features
 
    except Exception as e:
        print(f"Error retrieving features: {e}")
        return None

# 2. Load Locally Trained Model
def load_model():
    with open("model.pkl", "rb") as model_file:
        model = pickle.load(model_file)
    print("Model loaded successfully.")
    return model

# 3. Preprocess Features for Model Prediction
def preprocess_features(features):
    if not features:
        return None

    # Convert feature values to float
    latest_purchase_value = float(features.get("latest_purchase_value", 0.0))
    
    # Convert to model input format
    X_input = [[latest_purchase_value]]
    return X_input

# 4. Run Inference Using the Trained Model
def run_inference(model, X_input, customer_id):
    if not X_input:
        print("No valid input features for inference.")
        return None

    prediction = model.predict(X_input)
    print(f"Customer ID: {customer_id}, Prediction Result: {prediction[0]}")
    return prediction[0]


#  Execute the Inference Pipeline
customer_id = 86  
features = get_latest_features(customer_id)
X_input = preprocess_features(features)
ml_model = load_model()
prediction = run_inference(ml_model, X_input, customer_id)





