terraform {
  required_version = ">= 1.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Fetch project details (for project number)
data "google_project" "project" {}

# GCS Bucket for file uploads
resource "google_storage_bucket" "upload_bucket" {
  name                        = var.bucket_name
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  # Ensure the bucket is ready to send notifications
  lifecycle {
    prevent_destroy = false
  }
}

# Grant GCS service agent permission to publish events (required for Eventarc storage triggers)
resource "google_project_iam_binding" "gcs_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"

  members = [
    "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
  ]
}

# BigQuery Dataset
resource "google_bigquery_dataset" "dataset" {
  dataset_id                  = var.bigquery_dataset_id
  location                    = var.region
  description                 = "Dataset for serverless event-driven document processing pipeline"
  delete_contents_on_destroy  = true
}

# BigQuery Table
resource "google_bigquery_table" "table" {
  dataset_id = google_bigquery_dataset.dataset.dataset_id
  table_id   = var.bigquery_table_id
  
  deletion_protection = false

  schema = <<EOF
[
  {
    "name": "filename",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Name of the processed file"
  },
  {
    "name": "upload_time",
    "type": "TIMESTAMP",
    "mode": "REQUIRED",
    "description": "Timestamp of the upload event"
  },
  {
    "name": "tags",
    "type": "STRING",
    "mode": "REPEATED",
    "description": "Extracted OCR simulation tags"
  },
  {
    "name": "word_count",
    "type": "INTEGER",
    "mode": "REQUIRED",
    "description": "Simulated OCR word count"
  }
]
EOF
}

# Service Account for Cloud Run Service (least privilege)
resource "google_service_account" "cloud_run_sa" {
  account_id   = "document-processor-sa"
  display_name = "Cloud Run Document Processor Service Account"
}

# Grant Cloud Run SA access to GCS Bucket (Storage Object Viewer)
resource "google_storage_bucket_iam_member" "gcs_viewer" {
  bucket = google_storage_bucket.upload_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Grant Cloud Run SA access to BigQuery Dataset (Data Editor)
resource "google_bigquery_dataset_iam_member" "bq_editor" {
  dataset_id = google_bigquery_dataset.dataset.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Grant Cloud Run SA permission to run BigQuery jobs (BigQuery User on project level)
resource "google_project_iam_member" "bq_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Cloud Run Service for processing documents
resource "google_cloud_run_v2_service" "processor" {
  name     = "document-processor"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY" # Only internal/Eventarc traffic should call this

  template {
    service_account = google_service_account.cloud_run_sa.email

    containers {
      image = var.processor_image
      
      ports {
        container_port = 8080
      }

      env {
        name  = "BIGQUERY_DATASET"
        value = var.bigquery_dataset_id
      }
      env {
        name  = "BIGQUERY_TABLE"
        value = var.bigquery_table_id
      }
    }
  }

  # Allow Eventarc to create a trigger pointing here before the service is fully populated/deployed if needed
  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].containers[0].image, # Allow deploy scripts to update image out-of-band
    ]
  }
}

# Service Account for Eventarc Trigger
resource "google_service_account" "eventarc_sa" {
  account_id   = "eventarc-trigger-sa"
  display_name = "Eventarc Trigger Service Account"
}

# Grant Eventarc SA permission to invoke Cloud Run
resource "google_cloud_run_v2_service_iam_member" "eventarc_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.processor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.eventarc_sa.email}"
}

# Grant Eventarc SA receiver permissions
resource "google_project_iam_member" "eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.eventarc_sa.email}"
}

# Eventarc Trigger for GCS Object Creation
resource "google_eventarc_trigger" "gcs_trigger" {
  name     = "gcs-upload-trigger"
  location = var.region

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.upload_bucket.name
  }

  destination {
    cloud_run {
      service = google_cloud_run_v2_service.processor.name
      region  = var.region
      path    = "/"
    }
  }

  service_account = google_service_account.eventarc_sa.email

  # Wait for IAM permissions to apply first
  depends_on = [
    google_project_iam_binding.gcs_pubsub_publisher,
    google_cloud_run_v2_service_iam_member.eventarc_invoker,
    google_project_iam_member.eventarc_receiver
  ]
}
