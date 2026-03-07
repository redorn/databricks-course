# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Databricks training course. Contains sample datasets and a production-style ingestion stack:
- **DLT pipeline** (streaming, Auto Loader + apply_changes)
- **Parameterized Databricks Job** (batch orchestration, Python wheel + Delta MERGE INTO)
- **Terraform** for all infrastructure (schemas, external tables, pipeline, job)

Cloud: AWS (S3, `i3.xlarge` nodes).

---

## Commands

### Terraform
```bash
cd terraform

# Initialise providers
terraform init

# Deploy to dev (copy terraform.tfvars.example → terraform.tfvars first)
terraform apply

# Destroy
terraform destroy
```

### Python wheel (local build)
```bash
cd code/src
pip wheel . --no-deps -w dist
# produces: dist/io_lakehouse-0.1.0-py3-none-any.whl
# Terraform's null_resource.build_wheel does this automatically on apply.
```

### Run job via Databricks CLI
```bash
# First run per environment (creates schemas + external tables, then triggers DLT)
databricks jobs run-now --job-id <JOB_ID> \
  --job-parameters '{"run_setup":"true"}'

# Subsequent runs (all entities)
databricks jobs run-now --job-id <JOB_ID>

# Single entity run
databricks jobs run-now --job-id <JOB_ID> \
  --job-parameters '{"source_filter":"gizmobox","entity_filter":"customers"}'
```

---

## Project Structure

```
terraform/
  providers.tf                   # Databricks provider ~1.38
  variables.tf                   # environment, catalog, s3_landing_path, …
  main.tf                        # Calls 3 modules
  outputs.tf                     # pipeline_id, job_id
  terraform.tfvars.example       # Copy → terraform.tfvars (gitignored)
  modules/
    catalog/                     # databricks_schema (landing, raw)
                                 # databricks_sql_table (9 external tables)
    pipeline/                    # databricks_workspace_file + databricks_pipeline (DLT)
    jobs/                        # null_resource (build wheel) + databricks_dbfs_file
                                 # databricks_job (parameterized, 2-task)

code/
  src/
    io_lakehouse/
      entity_config.py           # EntityConfig dataclass + ENTITY_CONFIGS registry
      reader.py                  # Batch file reader (json/csv/binaryFile)
      writer.py                  # Delta MERGE INTO (SCD Type 1)
      ingest.py                  # Orchestration: filter + read + upsert per entity
      setup.py                   # CREATE SCHEMA/EXTERNAL TABLE (idempotent)
      main.py                    # CLI entry point (argparse → setup + ingest)
    pyproject.toml               # Package build; entry-point: io-lakehouse-ingest
  pipelines/
    raw_ingestion/
      pipeline.py                # DLT pipeline (Python file, no notebook)

assets/input_data/               # Sample landing-zone datasets for local dev/demo
```

---

## Architecture

### Medallion layers

| Layer   | UC schema            | Managed by                                 |
|---------|----------------------|--------------------------------------------|
| Landing | `{catalog}.landing`  | Terraform (external tables) + setup job    |
| Raw     | `{catalog}.raw`      | DLT pipeline (streaming) or batch job (MERGE INTO) |

### Batch job flow

```
Job parameter overrides (catalog, s3_landing_path, source_filter, …)
       │
       ▼
Task 1 – setup (python_wheel_task)
  if run_setup=true → CREATE SCHEMA + CREATE EXTERNAL TABLE
  run_ingestion():
    spark.read(format) from S3 landing
    → Delta MERGE INTO catalog.raw.{source}_{entity}
       │
       ▼
Task 2 – run_pipeline (pipeline_task)
  Triggers DLT pipeline update (Auto Loader + apply_changes)
```

### DLT pipeline flow (per entity)

```
S3 landing files
  └─[Auto Loader cloudFiles]─→  lnd_{source}_{entity}   (streaming DLT table)
                                        │
                                [APPLY CHANGES INTO, SCD Type 1]
                                        │
                                 {source}_{entity}        (Raw Delta, CDF enabled)
```

### Adding a new entity

1. Add an `EntityConfig` to `ENTITY_CONFIGS` in `code/src/io_lakehouse/entity_config.py`.
2. Add an entry to `local.landing_tables` in `terraform/modules/catalog/main.tf`.
3. `terraform apply` + re-run the job with `run_setup=true`.

No other files need changing.

### Job parameters

| Parameter        | Default           | Description                              |
|------------------|-------------------|------------------------------------------|
| `catalog`        | `var.catalog`     | Unity Catalog name                       |
| `s3_landing_path`| `var.s3_*`        | S3 root of the landing zone              |
| `raw_schema`     | `raw`             | Target schema for raw Delta tables       |
| `landing_schema` | `landing`         | Schema for external landing tables       |
| `source_filter`  | `""`              | Restrict to one source system (empty=all)|
| `entity_filter`  | `""`              | Restrict to one entity (empty=all)       |
| `run_setup`      | `"false"`         | `"true"` on first run per environment    |

### Unity Catalog naming

- Dev:     `io_lakehouse_dev`
- Staging: `io_lakehouse_staging`
- Prod:    `io_lakehouse`

Set via `catalog` variable in `terraform.tfvars`.

---

## Data sources

| Source     | Entity             | Format     | Primary key(s)             | Sequence by            |
|------------|--------------------|------------|----------------------------|------------------------|
| gizmobox   | customers          | JSON       | customer_id                | created_timestamp      |
| gizmobox   | addresses          | TSV (CSV)  | customer_id, address_type  | _ingestion_timestamp   |
| gizmobox   | orders             | JSON       | order_id                   | transaction_timestamp  |
| gizmobox   | payments           | CSV        | payment_id                 | payment_timestamp      |
| gizmobox   | memberships        | binaryFile | path                       | modificationTime       |
| circuitbox | customers          | JSON       | customer_id                | created_date           |
| circuitbox | addresses          | CSV        | customer_id                | created_date           |
| circuitbox | orders             | JSON       | order_id                   | order_timestamp        |
| market     | stock_prices       | JSON       | stock_id, trading_date     | trading_date           |
| market     | top_tech_companies | CSV        | company_name               | _ingestion_timestamp   |

`gizmobox/refunds` comes from Azure SQL (DDL only in repo) — ingest separately via JDBC.
