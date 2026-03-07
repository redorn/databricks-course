output "landing_schema_id" {
  value = databricks_schema.landing.id
}

output "raw_schema_id" {
  value = databricks_schema.raw.id
}

output "wheel_volume_path" {
  description = "UC volume path for Python wheel uploads (e.g. /Volumes/catalog/artifacts/libs)"
  value       = databricks_volume.libs.volume_path
}
