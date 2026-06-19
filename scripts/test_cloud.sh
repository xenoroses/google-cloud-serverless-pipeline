#!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status
set -e

echo "=========================================================="
echo "      Cloud Verification Test: Document Pipeline          "
echo "=========================================================="

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform is required to read resource outputs."
    exit 1
fi

# Fetch outputs from Terraform
echo "Reading infrastructure config from Terraform outputs..."
if [ -d "terraform" ]; then
    cd terraform
fi

BUCKET_NAME=$(terraform output -raw upload_bucket_name 2>/dev/null)
BQ_TABLE=$(terraform output -raw bigquery_table_id 2>/dev/null)

if [ -z "$BUCKET_NAME" ] || [ -z "$BQ_TABLE" ]; then
    echo "Error: Could not retrieve Terraform outputs. Ensure you have run 'terraform apply' first."
    exit 1
fi

# Go back to parent directory if we moved
if [ "$(basename "$PWD")" = "terraform" ]; then
    cd ..
fi

echo "Configuration found:"
echo "  - Upload Bucket:  gs://$BUCKET_NAME"
echo "  - BigQuery Table: $BQ_TABLE"
echo "----------------------------------------------------------"

# 1. Create a dummy test file
TEST_FILE="cloud_invoice_test.pdf"
echo "Creating dummy test document: $TEST_FILE..."
echo "Simulated Invoice Content for Cloud OCR Validation." > "$TEST_FILE"

# 2. Upload file to GCS
echo "Uploading file to GCS bucket..."
gcloud storage cp "$TEST_FILE" "gs://$BUCKET_NAME/$TEST_FILE"

# 3. Wait for event processing
echo "File uploaded. Waiting 10 seconds for Eventarc triggering, Cloud Run processing, and BigQuery streaming..."
sleep 10

# 4. Verify BigQuery streaming
echo "Querying BigQuery table for processed metadata..."
# Extract project, dataset, and table from BQ_TABLE (which is in format project.dataset.table)
# Run the bq query command
bq query --use_legacy_sql=false \
    "SELECT filename, upload_time, tags, word_count FROM \`$BQ_TABLE\` WHERE filename = '$TEST_FILE' LIMIT 1"

echo "----------------------------------------------------------"
echo "Verification complete!"
# Clean up local file
rm "$TEST_FILE"
