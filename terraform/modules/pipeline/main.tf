terraform {
  required_providers {
    databricks = {
      source = "databricks/databricks"
    }
  }
}

# Upload the DLT pipeline Python source file to the Databricks workspace.
resource "databricks_workspace_file" "pipeline" {
  path   = "/Shared/io-lakehouse/${var.environment}/raw_ingestion_pipeline.py"
  source = "${path.module}/../../../code/pipelines/raw_ingestion/pipeline.py"
}

resource "databricks_pipeline" "raw_ingestion" {
  name       = "io-lakehouse-raw-ingestion-${var.environment}"
  serverless = true        # serverless DLT — no cluster block needed
  catalog    = var.catalog
  target     = "${var.raw_schema}_dlt"

  # Configuration keys read by pipeline.py via spark.conf.get(...)
  configuration = {
    s3_landing_path = var.s3_landing_path
    catalog         = var.catalog
    raw_schema      = var.raw_schema
    source_filter   = var.source_filter
    entity_filter   = var.entity_filter
  }

  # Install the io_lakehouse wheel so `from io_lakehouse...` imports work.
  # For serverless DLT, dependencies go in the environment block (not cluster).
  environment {
    dependencies = [
      "${var.wheel_volume_path}/io_lakehouse-0.1.0-py3-none-any.whl",
    ]
  }

  library {
    file {
      path = databricks_workspace_file.pipeline.path
    }
  }

  channel     = "CURRENT"
  continuous  = false   # triggered mode; set true for near-real-time
  development = var.environment == "dev"
}
