locals {
  wheel_src_dir = "${path.module}/../../../code/src"
  wheel_version = "0.1.0"
  wheel_file    = "io_lakehouse-${local.wheel_version}-py3-none-any.whl"
  wheel_local   = "${local.wheel_src_dir}/dist/${local.wheel_file}"
  wheel_remote  = "${var.wheel_volume_path}/${local.wheel_file}"
}

# ── Build the Python wheel locally ────────────────────────────────────────────
# Triggers a rebuild whenever any source Python file changes.
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

# ── Upload wheel to Unity Catalog Volume ──────────────────────────────────────
# Uses databricks_file (not deprecated databricks_dbfs_file).
# Serverless compute can only read from /Volumes/ and /Workspace/ – not DBFS.
resource "databricks_file" "wheel" {
  depends_on = [null_resource.build_wheel]
  source     = local.wheel_local
  path       = local.wheel_remote
}

# ── Parameterized ingestion job (serverless) ──────────────────────────────────
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
    default = ""   # empty = all source systems
  }
  parameter {
    name    = "entity_filter"
    default = ""   # empty = all entities
  }
  parameter {
    name    = "run_setup"
    default = "false"   # set "true" on first run per environment
  }

  # ── Serverless environment: installs the wheel before the task runs ─────────
  # For serverless compute, libraries are declared here (NOT in task.libraries).
  environment {
    environment_key = "default"
    spec {
      client = "1"
      dependencies = [
        # Wheel is read from the UC volume uploaded above
        databricks_file.wheel.path,
      ]
    }
  }

  # ── Task 1: Setup + batch ingestion (python_wheel_task, serverless) ─────────
  task {
    task_key        = "setup_and_ingest"
    environment_key = "default"   # links to the environment block above
    # No new_cluster / existing_cluster_id / job_cluster_key → serverless compute

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
  }

  # ── Task 2: Trigger DLT pipeline ─────────────────────────────────────────────
  task {
    task_key = "run_pipeline"

    depends_on {
      task_key = "setup_and_ingest"
    }

    pipeline_task {
      pipeline_id  = var.pipeline_id
      full_refresh = false
    }
  }

  tags = {
    environment = var.environment
    project     = "io-lakehouse"
    layer       = "raw"
  }
}
