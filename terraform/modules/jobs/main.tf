locals {
  wheel_src_dir = "${path.module}/../../../code/src"
  wheel_path    = "${local.wheel_src_dir}/dist/io_lakehouse-0.1.0-py3-none-any.whl"
  dbfs_wheel    = "dbfs:/FileStore/io-lakehouse/wheels/io_lakehouse-0.1.0-py3-none-any.whl"
}

# ── Build the Python wheel locally ────────────────────────────────────────────
# Triggers a rebuild whenever any source file changes.
resource "null_resource" "build_wheel" {
  triggers = {
    src_hash = sha256(join("||", [
      for f in sort(fileset(local.wheel_src_dir, "io_lakehouse/**/*.py")) :
      filesha256("${local.wheel_src_dir}/${f}")
    ]))
  }

  provisioner "local-exec" {
    command     = "pip wheel . --no-deps -w dist --quiet"
    working_dir = local.wheel_src_dir
  }
}

# ── Upload wheel to DBFS ──────────────────────────────────────────────────────
resource "databricks_dbfs_file" "wheel" {
  depends_on = [null_resource.build_wheel]
  source     = local.wheel_path
  path       = local.dbfs_wheel
}

# ── Parameterized ingestion job ───────────────────────────────────────────────
resource "databricks_job" "raw_ingestion" {
  name = "io-lakehouse-raw-ingestion-${var.environment}"

  # ── Job-level parameters (overridable per run) ──────────────────────────────
  parameter {
    name    = "catalog"
    default = var.catalog
  }
  parameter {
    name    = "s3_landing_path"
    default = var.s3_landing_path
  }
  parameter {
    name    = "raw_schema"
    default = var.raw_schema
  }
  parameter {
    name    = "landing_schema"
    default = var.landing_schema
  }
  parameter {
    name    = "source_filter"
    default = ""   # empty = process all source systems
  }
  parameter {
    name    = "entity_filter"
    default = ""   # empty = process all entities
  }
  parameter {
    name    = "run_setup"
    default = "false"   # set "true" on first run per environment
  }

  # ── Task 1: Setup – create schemas and external landing tables ───────────────
  task {
    task_key = "setup"

    new_cluster {
      spark_version = var.spark_version
      node_type_id  = var.node_type_id
      num_workers   = 1
      spark_conf = {
        "spark.databricks.delta.preview.enabled" = "true"
      }
    }

    python_wheel_task {
      package_name = "io_lakehouse"
      entry_point  = "io-lakehouse-ingest"

      named_parameters = {
        catalog           = "{{job.parameters.catalog}}"
        s3-landing-path   = "{{job.parameters.s3_landing_path}}"
        raw-schema        = "{{job.parameters.raw_schema}}"
        landing-schema    = "{{job.parameters.landing_schema}}"
        source-filter     = "{{job.parameters.source_filter}}"
        entity-filter     = "{{job.parameters.entity_filter}}"
        run-setup         = "{{job.parameters.run_setup}}"
      }
    }

    library {
      whl = databricks_dbfs_file.wheel.dbfs_path
    }
  }

  # ── Task 2: Trigger DLT pipeline ─────────────────────────────────────────────
  task {
    task_key = "run_pipeline"

    depends_on {
      task_key = "setup"
    }

    pipeline_task {
      pipeline_id        = var.pipeline_id
      full_refresh       = false
    }
  }

  # ── Job-level compute for the pipeline task (uses pipeline's own cluster) ───

  tags = {
    environment = var.environment
    project     = "io-lakehouse"
    layer       = "raw"
  }
}
