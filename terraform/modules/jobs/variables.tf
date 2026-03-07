variable "environment"       { type = string }
variable "catalog"           { type = string }
variable "raw_schema"        { type = string }
variable "landing_schema"    { type = string }
variable "s3_landing_path"   { type = string }
variable "spark_version"     { type = string }  # kept for reference / future classic tasks
variable "pipeline_id"       { type = string }
variable "wheel_volume_path" {
  description = "UC volume path where the Python wheel is stored (e.g. /Volumes/catalog/artifacts/libs)"
  type        = string
}
