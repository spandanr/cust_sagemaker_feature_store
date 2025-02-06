# SageMaker Feature Store Implementation

This project demonstrates the use of AWS SageMaker Feature Store for managing machine learning features. It includes:

## Code Components

### **1️⃣ `setup.sh`**
- Provisions all necessary AWS resources:
  - Creates **SageMaker Feature Store**.
  - Sets up **Athena** for historical queries.
  - Creates **S3 buckets** for storing feature data.
  - Configures **IAM roles and policies**.

### **2️⃣ `cleanup.sh`**
- Deletes all AWS resources to free up cloud costs.

### **3️⃣ `historical_features.py`**
- Fetches historical feature data from Athena putting in a date filter
- Trains a Random Forest Regressor to predict the loyalty score based on the purchase score
- Saves the trained model to S3.

### **4️⃣ `update_feature_store.py`**
- Reads data from a simulated real-time data stream from a csv file test_task_data.csv
- Updates the SageMaker Feature Store with the latest feature values for purchase_value and loyalty_score

### **5️⃣ `real_time_inference.py`**
- Fetches the latest feature values from SageMaker Feature Store.
- Loads the trained model and makes predictions.

---

## Prerequisites

Ensure the following are installed before running the project:

✅ **AWS CLI** – Install & Configure AWS credentials  
aws configure

✅ ## Create the python virtual environment and install the dependencies in requirements.txt
python -m venv venv
source venv/bin/activate  # macOS/Linux
venv\Scripts\activate  # Windows
pip install -r requirements.txt


Execution Sequence

. Set Up AWS Resources: Run ./setup.sh in bash

2. Stream Data to Feature Store: python update_feature_store.py

3. Pull historical features from Athena tables and train a model: python historical_features.py

4. Perform inference on latest features: python real_time_inference.py

5. Clean up AWS resources : ./cleanup.sh


AUTHOR: Spandan Rakshit




