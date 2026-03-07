locals {
  base = trimsuffix(var.s3_landing_path, "/")

  # External landing tables: key = table name, value = config
  landing_tables = {
    "gizmobox_customers" = {
      format   = "JSON"
      location = "${local.base}/gizmobox/customers/"
      options  = {}
    }
    "gizmobox_addresses" = {
      format   = "CSV"
      location = "${local.base}/gizmobox/addresses/"
      # TSV: tab separator + header
      options = { sep = "\\t", header = "true" }
    }
    "gizmobox_orders" = {
      format   = "JSON"
      location = "${local.base}/gizmobox/orders/"
      options  = {}
    }
    "gizmobox_payments" = {
      format   = "CSV"
      location = "${local.base}/gizmobox/payments/"
      options  = { header = "true" }
    }
    "circuitbox_customers" = {
      format   = "JSON"
      location = "${local.base}/circuitbox/customers/"
      options  = {}
    }
    "circuitbox_addresses" = {
      format   = "CSV"
      location = "${local.base}/circuitbox/addresses/"
      options  = { header = "true" }
    }
    "circuitbox_orders" = {
      format   = "JSON"
      location = "${local.base}/circuitbox/orders/"
      options  = {}
    }
    "market_stock_prices" = {
      format   = "JSON"
      location = "${local.base}/stock_prices/"
      options  = {}
    }
    "market_top_tech_companies" = {
      format   = "CSV"
      location = "${local.base}/top_tech_companies/"
      options  = { header = "true" }
    }
  }
}

# ── Schemas ───────────────────────────────────────────────────────────────────

resource "databricks_schema" "landing" {
  catalog_name = var.catalog
  name         = var.landing_schema
  comment      = "External tables on the S3 landing zone (io-lakehouse)"
  properties = {
    environment = var.environment
    layer       = "landing"
  }
}

resource "databricks_schema" "raw" {
  catalog_name = var.catalog
  name         = var.raw_schema
  comment      = "Raw Delta tables – upserted from landing (io-lakehouse)"
  properties = {
    environment = var.environment
    layer       = "raw"
  }
}

# ── External landing tables ───────────────────────────────────────────────────
# Table properties include format options (header, sep).
# These propagate to the Spark reader when tables are queried via Unity Catalog.
# If a table needs complex OPTIONS not supported here, run the job with
# --run-setup true to create it via Spark SQL (idempotent).

resource "databricks_sql_table" "landing" {
  for_each = local.landing_tables

  catalog_name       = var.catalog
  schema_name        = var.landing_schema
  name               = each.key
  table_type         = "EXTERNAL"
  data_source_format = each.value.format
  storage_location   = each.value.location
  comment            = "Landing external table: ${each.key}"

  properties = merge(
    each.value.options,
    {
      environment = var.environment
      layer       = "landing"
    }
  )

  depends_on = [databricks_schema.landing]
}
