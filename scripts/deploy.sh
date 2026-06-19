#!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status
set -e

# Clear terminal
clear

echo "=========================================================="
echo "   Serverless Event-Driven Document Pipeline Deployer     "
echo "=========================================================="

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI is not installed. Please install it to proceed."
    exit 1
fi

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform is not installed. Please install it to proceed."
    exit 1
fi

# Get current GCP Project ID from configuration or prompt
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    read -p "Enter your Google Cloud Project ID: " PROJECT_ID
    if [ -z "$PROJECT_ID" ]; then
        echo "Project ID cannot be empty."
        exit 1
    fi
fi

# Set defaults
REGION="us-central1"
BUCKET_NAME="doc-pipeline-uploads-${PROJECT_ID}"
REPO_NAME="pipeline-repo"
IMAGE_NAME="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/processor:latest"

echo "Configuration Details:"
echo "  - Project ID: $PROJECT_ID"
echo "  - Region:     $REGION"
echo "  - Bucket:     $BUCKET_NAME"
echo "  - Repo:       $REPO_NAME"
echo "  - Image:      $IMAGE_NAME"
echo "----------------------------------------------------------"

# Ensure API services are enabled
echo "Enabling necessary GCP APIs (Artifact Registry, Cloud Build, Cloud Run, Eventarc, BigQuery, Pub/Sub)..."
gcloud services enable \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    eventarc.googleapis.com \
    bigquery.googleapis.com \
    pubsub.googleapis.com \
    storage.googleapis.com \
    --project="$PROJECT_ID"

# Create Artifact Registry if it doesn't exist
echo "Creating Artifact Registry repository if not exists..."
gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for serverless pipeline" \
    --project="$PROJECT_ID" 2>/dev/null || echo "Repository already exists."

# Build and Push image using Cloud Build (Serverless Build)
echo "Building and pushing container image via Cloud Build..."
gcloud builds submit --tag "$IMAGE_NAME" src/processor/ --project="$PROJECT_ID"

# Terraform Provisioning
echo "Initializing Terraform..."
cd terraform
terraform init

echo "Applying Terraform configuration..."
terraform apply \
    -var="project_id=$PROJECT_ID" \
    -var="region=$REGION" \
    -var="bucket_name=$BUCKET_NAME" \
    -var="processor_image=$IMAGE_NAME" \
    -auto-approve

echo "----------------------------------------------------------"
echo "Deployment successful!"
echo "You can now test uploads to the bucket: gs://$BUCKET_NAME"
echo "----------------------------------------------------------"
