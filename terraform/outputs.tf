output "pipeline_id" {
  description = "DLT pipeline ID (streaming ingestion)"
  value       = module.pipeline.pipeline_id
}

output "job_id" {
  description = "Parameterized batch ingestion job ID"
  value       = module.jobs.job_id
}

output "catalog" {
  description = "Unity Catalog name used in this deployment"
  value       = var.catalog
}

output "landing_schema" {
  description = "Full landing schema identifier"
  value       = "${var.catalog}.${var.landing_schema}"
}

output "raw_schema" {
  description = "Full raw schema identifier"
  value       = "${var.catalog}.${var.raw_schema}"
}
