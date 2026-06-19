variable "project_id" {
  type        = string
  description = "The GCP project ID to deploy resources to."
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "The GCP region to deploy resources to."
}

variable "bucket_name" {
  type        = string
  description = "The name of the GCS bucket for uploading files. Must be globally unique."
}

variable "bigquery_dataset_id" {
  type        = string
  default     = "document_pipeline"
  description = "The ID of the BigQuery dataset."
}

variable "bigquery_table_id" {
  type        = string
  default     = "processed_metadata"
  description = "The ID of the BigQuery table to stream metadata into."
}

variable "processor_image" {
  type        = string
  default     = "us-central1-docker.pkg.dev/PROJECT_ID/pipeline-repo/processor:latest"
  description = "The container image URI for the Cloud Run processor. Will be overwritten by build script."
}
