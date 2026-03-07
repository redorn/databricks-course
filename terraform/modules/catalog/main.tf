terraform {
  required_providers {
    databricks = {
      source = "databricks/databricks"
    }
  }
}

# Catalog is pre-created via SQL (CREATE CATALOG IF NOT EXISTS) because
# Databricks-managed default storage does not allow catalog creation via the
# Terraform resource or REST API. We reference it here as a data source.
data "databricks_catalog" "this" {
  name = var.catalog
}

# ── Schemas ───────────────────────────────────────────────────────────────────
# An "artifacts" schema hosts the UC volume for CI/CD wheel uploads.

resource "databricks_schema" "artifacts" {
  depends_on   = [data.databricks_catalog.this]
  catalog_name = var.catalog
  name         = "artifacts"
  comment      = "CI/CD deployment artifacts (Python wheels, etc.)"
  properties = {
    environment = var.environment
    layer       = "artifacts"
  }
}

# Managed volume that holds Python wheels uploaded during CI/CD.
# Serverless jobs and DLT pipelines install the wheel from here.
resource "databricks_volume" "libs" {
  catalog_name = var.catalog
  schema_name  = databricks_schema.artifacts.name
  name         = "libs"
  volume_type  = "MANAGED"
  comment      = "Python wheel artifacts for io-lakehouse pipelines"

  depends_on = [databricks_schema.artifacts]
}

resource "databricks_schema" "landing" {
  depends_on   = [data.databricks_catalog.this]
  catalog_name = var.catalog
  name         = var.landing_schema
  comment      = "Landing zone for raw source files (io-lakehouse)"
  properties = {
    environment = var.environment
    layer       = "landing"
  }
}

# Managed volume that holds raw source files (JSON/CSV/TSV).
# Upload test data here; the ingestion job reads from this volume path.
resource "databricks_volume" "files" {
  catalog_name = var.catalog
  schema_name  = databricks_schema.landing.name
  name         = "files"
  volume_type  = "MANAGED"
  comment      = "Raw source files for ingestion (replaces S3 landing bucket)"

  depends_on = [databricks_schema.landing]
}

resource "databricks_schema" "raw" {
  depends_on   = [data.databricks_catalog.this]
  catalog_name = var.catalog
  name         = var.raw_schema
  comment      = "Raw Delta tables – batch ingestion (io-lakehouse)"
  properties = {
    environment = var.environment
    layer       = "raw"
  }
}

resource "databricks_schema" "raw_dlt" {
  depends_on   = [data.databricks_catalog.this]
  catalog_name = var.catalog
  name         = "${var.raw_schema}_dlt"
  comment      = "Raw Delta tables – DLT pipeline ingestion (io-lakehouse)"
  properties = {
    environment = var.environment
    layer       = "raw_dlt"
  }
}

# External landing tables are not managed here.
# Databricks recommends using your own S3 bucket (registered as a UC External
# Location) for the landing zone. Databricks-managed storage is reserved for
# managed Delta tables (raw, silver, gold layers).
# In production: add databricks_storage_credential + databricks_external_location
# pointing to your own bucket, then add databricks_sql_table here.
# For this demo: the ingestion job reads S3 paths directly via spark.read.
