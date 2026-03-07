# Upload the DLT pipeline Python source to the Databricks workspace.
# The pipeline references it by workspace path.
resource "databricks_workspace_file" "pipeline" {
  path   = "/Shared/io-lakehouse/${var.environment}/raw_ingestion_pipeline.py"
  source = "${path.module}/../../../code/pipelines/raw_ingestion/pipeline.py"
}

resource "databricks_pipeline" "raw_ingestion" {
  name    = "io-lakehouse-raw-ingestion-${var.environment}"
  catalog = var.catalog
  target  = var.raw_schema

  # These values are read by pipeline.py via spark.conf.get(...)
  configuration = {
    s3_landing_path = var.s3_landing_path
    catalog         = var.catalog
    raw_schema      = var.raw_schema
    source_filter   = var.source_filter
    entity_filter   = var.entity_filter
  }

  library {
    # The io_lakehouse wheel (built and uploaded by the jobs module) must be
    # installed on the pipeline cluster so `from io_lakehouse...` imports work.
    # Reference it here after the jobs module uploads it.
    file {
      path = databricks_workspace_file.pipeline.path
    }
  }

  cluster {
    label = "default"
    autoscale {
      min_workers = 1
      max_workers = var.max_workers
      mode        = "ENHANCED"
    }
    node_type_id = var.node_type_id
    spark_conf = {
      "spark.databricks.delta.optimizeWrite.enabled" = "true"
      "spark.databricks.delta.autoCompact.enabled"   = "true"
    }
  }

  channel    = "CURRENT"
  photon     = true
  continuous = false   # set true for near-real-time streaming
  development = var.environment == "dev"
}
