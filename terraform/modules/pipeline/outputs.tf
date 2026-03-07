output "pipeline_id" {
  description = "DLT pipeline ID"
  value       = databricks_pipeline.raw_ingestion.id
}
