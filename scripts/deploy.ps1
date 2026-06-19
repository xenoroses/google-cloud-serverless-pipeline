# PowerShell deployment script for Windows environments
$ErrorActionPreference = "Stop"

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Serverless Event-Driven Document Pipeline Deployer     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Check dependencies
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Error "gcloud CLI is not installed. Please install it to proceed."
}

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Error "Terraform is not installed. Please install it to proceed."
}

# Get current GCP project ID
$PROJECT_ID = gcloud config get-value project 2>$null
if ([string]::IsNullOrEmpty($PROJECT_ID) -or $PROJECT_ID -eq "(unset)") {
    $PROJECT_ID = Read-Host "Enter your Google Cloud Project ID"
    if ([string]::IsNullOrEmpty($PROJECT_ID)) {
        Write-Error "Project ID cannot be empty."
    }
}

# Set defaults
$REGION = "us-central1"
$BUCKET_NAME = "doc-pipeline-uploads-$($PROJECT_ID.ToLower())"
$REPO_NAME = "pipeline-repo"
$IMAGE_NAME = "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/processor:latest"

Write-Host "Configuration Details:"
Write-Host "  - Project ID: $PROJECT_ID"
Write-Host "  - Region:     $REGION"
Write-Host "  - Bucket:     $BUCKET_NAME"
Write-Host "  - Repo:       $REPO_NAME"
Write-Host "  - Image:      $IMAGE_NAME"
Write-Host "----------------------------------------------------------"

# Enable APIs
Write-Host "Enabling Google Cloud APIs..."
gcloud services enable `
    artifactregistry.googleapis.com `
    cloudbuild.googleapis.com `
    run.googleapis.com `
    eventarc.googleapis.com `
    bigquery.googleapis.com `
    pubsub.googleapis.com `
    storage.googleapis.com `
    --project=$PROJECT_ID

# Create Repository
Write-Host "Creating Artifact Registry..."
try {
    gcloud artifacts repositories create $REPO_NAME `
        --repository-format=docker `
        --location=$REGION `
        --description="Docker repository for serverless pipeline" `
        --project=$PROJECT_ID 2>$null
} catch {
    Write-Host "Repository may already exist."
}

# Build Image
Write-Host "Submitting Cloud Build..."
gcloud builds submit --tag $IMAGE_NAME src/processor/ --project=$PROJECT_ID

# Terraform deploy
Write-Host "Initializing Terraform..."
Push-Location terraform
try {
    terraform init
    Write-Host "Applying Terraform config..."
    terraform apply `
        -var="project_id=$PROJECT_ID" `
        -var="region=$REGION" `
        -var="bucket_name=$BUCKET_NAME" `
        -var="processor_image=$IMAGE_NAME" `
        -auto-approve
} finally {
    Pop-Location
}

Write-Host "----------------------------------------------------------" -ForegroundColor Green
Write-Host "Deployment successful!" -ForegroundColor Green
Write-Host "You can now test uploads to the bucket: gs://$BUCKET_NAME" -ForegroundColor Green
Write-Host "----------------------------------------------------------" -ForegroundColor Green
