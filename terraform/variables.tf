variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "databricks_host" {
  description = "Databricks workspace URL (e.g. https://dbc-xxxx.cloud.databricks.com)"
  type        = string
}

variable "databricks_token" {
  description = "Databricks personal access token or service-principal token"
  type        = string
  sensitive   = true
}

variable "catalog" {
  description = "Unity Catalog name for the io-lakehouse project"
  type        = string
}

variable "s3_landing_path" {
  description = "S3 root path of the landing zone (no trailing slash), e.g. s3://bucket/landing"
  type        = string
}

variable "raw_schema" {
  description = "Schema name for raw Delta tables"
  type        = string
  default     = "raw"
}

variable "landing_schema" {
  description = "Schema name for external landing tables"
  type        = string
  default     = "landing"
}

variable "spark_version" {
  description = "Databricks Runtime version (used by future classic tasks if needed)"
  type        = string
  default     = "15.4.x-scala2.12"
}
