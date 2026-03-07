output "batch_job_id" {
  description = "Batch ingestion job ID (Python wheel)"
  value       = databricks_job.batch_ingestion.id
}

output "dlt_job_id" {
  description = "DLT pipeline ingestion job ID"
  value       = databricks_job.dlt_ingestion.id
}
