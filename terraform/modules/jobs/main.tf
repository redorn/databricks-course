terraform {
  required_providers {
    databricks = {
      source = "databricks/databricks"
    }
  }
}

locals {
  wheel_src_dir = "${path.module}/../../../code/src"
  wheel_version = "0.1.0"
  wheel_file    = "io_lakehouse-${local.wheel_version}-py3-none-any.whl"
  wheel_local   = "${local.wheel_src_dir}/dist/${local.wheel_file}"
  wheel_remote  = "${var.wheel_volume_path}/${local.wheel_file}"
}

# ── Build the Python wheel locally ────────────────────────────────────────────
resource "null_resource" "build_wheel" {
  triggers = {
    src_hash = sha256(join("||", [
      for f in sort(fileset(local.wheel_src_dir, "io_lakehouse/**/*.py")) :
      filesha256("${local.wheel_src_dir}/${f}")
    ]))
  }

  provisioner "local-exec" {
    command     = "${pathexpand("~")}/.pyenv/versions/3.11.9/bin/pip wheel . --no-deps -w dist --quiet"
    working_dir = local.wheel_src_dir
  }
}

# ── Upload wheel to Unity Catalog Volume ──────────────────────────────────────
resource "databricks_file" "wheel" {
  depends_on = [null_resource.build_wheel]
  source     = local.wheel_local
  path       = local.wheel_remote

  lifecycle {
    replace_triggered_by = [null_resource.build_wheel.id]
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# Job 1: Batch ingestion (Python wheel – setup + MERGE INTO)
# ══════════════════════════════════════════════════════════════════════════════
resource "databricks_job" "batch_ingestion" {
  name = "io-lakehouse-batch-ingestion-${var.environment}"

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
    default = ""
  }
  parameter {
    name    = "entity_filter"
    default = ""
  }
  parameter {
    name    = "run_setup"
    default = "false"
  }

  environment {
    environment_key = "default"
    spec {
      client       = "2"
      dependencies = [databricks_file.wheel.path]
    }
  }

  task {
    task_key        = "setup_and_ingest"
    environment_key = "default"

    python_wheel_task {
      package_name = "io_lakehouse"
      entry_point  = "io-lakehouse-ingest"

      named_parameters = {
        catalog          = "{{job.parameters.catalog}}"
        s3_landing_path  = "{{job.parameters.s3_landing_path}}"
        raw_schema       = "{{job.parameters.raw_schema}}"
        landing_schema   = "{{job.parameters.landing_schema}}"
        source_filter    = "{{job.parameters.source_filter}}"
        entity_filter    = "{{job.parameters.entity_filter}}"
        run_setup        = "{{job.parameters.run_setup}}"
      }
    }
  }

  tags = {
    environment = var.environment
    project     = "io-lakehouse"
    layer       = "raw"
    mode        = "batch"
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# Job 2: DLT pipeline ingestion (Auto Loader + APPLY CHANGES)
# ══════════════════════════════════════════════════════════════════════════════
resource "databricks_job" "dlt_ingestion" {
  name = "io-lakehouse-dlt-ingestion-${var.environment}"

  task {
    task_key = "run_pipeline"

    pipeline_task {
      pipeline_id  = var.pipeline_id
      full_refresh = false
    }
  }

  tags = {
    environment = var.environment
    project     = "io-lakehouse"
    layer       = "raw"
    mode        = "dlt"
  }
}
