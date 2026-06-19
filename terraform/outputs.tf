output "upload_bucket_name" {
  value       = google_storage_bucket.upload_bucket.name
  description = "The name of the GCS upload bucket."
}

output "cloud_run_url" {
  value       = google_cloud_run_v2_service.processor.uri
  description = "The URL of the deployed Cloud Run service."
}

output "bigquery_table_id" {
  value       = "${var.project_id}.${google_bigquery_dataset.dataset.dataset_id}.${google_bigquery_table.table.table_id}"
  description = "The fully qualified BigQuery table ID."
}

output "eventarc_trigger_name" {
  value       = google_eventarc_trigger.gcs_trigger.name
  description = "The name of the Eventarc trigger."
}
