"""
IO Lakehouse – DLT Pipeline (streaming / continuous mode)
=========================================================
For batch processing use the parameterized Databricks Job instead.

Configuration keys (set in terraform/modules/pipeline/main.tf → configuration {}):
  s3_landing_path  – S3 root of the landing zone
  catalog          – Unity Catalog name
  raw_schema       – Target schema (default: raw)
  source_filter    – Restrict to one source system; empty = all (optional)
  entity_filter    – Restrict to one entity; empty = all (optional)

Table naming (all land in the pipeline's catalog.raw schema):
  lnd_{source}_{entity}  – Auto Loader streaming table  (landing layer)
  {source}_{entity}      – Upserted Delta table          (raw layer)
"""

import dlt
from pyspark.sql import functions as F
from pyspark.sql.types import StringType

from io_lakehouse.entity_config import ENTITY_CONFIGS, EntityConfig

# ── Pipeline-level configuration ──────────────────────────────────────────────
S3_LANDING_PATH = spark.conf.get("s3_landing_path")
SOURCE_FILTER   = spark.conf.get("source_filter", "")
ENTITY_FILTER   = spark.conf.get("entity_filter", "")

_active = [
    cfg for cfg in ENTITY_CONFIGS
    if (not SOURCE_FILTER or cfg.source == SOURCE_FILTER)
    and (not ENTITY_FILTER or cfg.entity == ENTITY_FILTER)
]


# ── Helpers ───────────────────────────────────────────────────────────────────

def _autoloader_opts(cfg: EntityConfig) -> dict:
    opts = {
        "cloudFiles.format":            cfg.file_format,
        "cloudFiles.schemaLocation":    cfg.schema_location(S3_LANDING_PATH),
        "cloudFiles.inferColumnTypes":  "true",
        "cloudFiles.schemaEvolutionMode": "addNewColumns",
        "cloudFiles.useNotifications":  "false",   # S3 directory-listing mode
    }
    if cfg.file_format != "binaryFile":
        opts["header"] = str(cfg.header).lower()
        if cfg.separator:
            opts["sep"] = cfg.separator
        if cfg.multiline:
            opts["multiLine"] = "true"
    return opts


# ── DLT table factories ───────────────────────────────────────────────────────

def register_landing(cfg: EntityConfig):
    """Auto Loader streaming table – landing layer."""

    @dlt.table(
        name=cfg.landing_table,
        comment=f"Auto Loader streaming ingest: {cfg.source}/{cfg.entity}",
        table_properties={
            "quality":                "landing",
            "source_system":          cfg.source,
            "entity":                 cfg.entity,
            "pipelines.reset.allowed": "false",
        },
    )
    def _tbl():
        stream = (
            spark.readStream
            .format("cloudFiles")
            .options(**_autoloader_opts(cfg))
            .load(cfg.landing_path(S3_LANDING_PATH))
        )
        if cfg.file_format == "binaryFile":
            return (
                stream
                .withColumnRenamed("path", "_source_file")
                .withColumnRenamed("modificationTime", "_source_modified_at")
                .withColumn("_ingestion_timestamp", F.current_timestamp())
            )
        return (
            stream
            .withColumn("_source_file",
                        F.col("_metadata.file_path").cast(StringType()))
            .withColumn("_source_modified_at",
                        F.col("_metadata.file_modification_time"))
            .withColumn("_ingestion_timestamp", F.current_timestamp())
        )

    return _tbl


def register_raw(cfg: EntityConfig):
    """Raw Delta table – SCD Type 1 upsert via APPLY CHANGES INTO."""

    dlt.create_streaming_table(
        name=cfg.raw_table,
        comment=f"Raw Delta table: {cfg.source}/{cfg.entity} (SCD Type 1)",
        table_properties={
            "quality":                          "raw",
            "source_system":                    cfg.source,
            "entity":                           cfg.entity,
            "delta.enableChangeDataFeed":       "true",
            "delta.autoOptimize.optimizeWrite": "true",
            "delta.autoOptimize.autoCompact":   "true",
            "pipelines.reset.allowed":          "false",
        },
    )

    dlt.apply_changes(
        target=cfg.raw_table,
        source=cfg.landing_table,
        keys=cfg.primary_keys,
        sequence_by=F.col(cfg.sequence_by),
        stored_as_scd_type=1,
    )


# ── Register all active entities ──────────────────────────────────────────────
# Factory functions ensure correct variable capture in closures.
for _cfg in _active:
    register_landing(_cfg)
    register_raw(_cfg)
