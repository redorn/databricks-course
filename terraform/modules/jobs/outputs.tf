output "job_id" {
  description = "Parameterized batch ingestion job ID"
  value       = databricks_job.raw_ingestion.id
}
