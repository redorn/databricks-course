"""Delta MERGE INTO writer for the raw layer.

Strategy: SCD Type 1 (last-write-wins).
  - First run  → create the Delta table and insert all rows.
  - Subsequent → merge on primary keys; update only when the incoming
                 record is not older than the stored one (sequence check).
"""

import logging
from typing import Dict, Any

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from delta.tables import DeltaTable

from io_lakehouse.entity_config import EntityConfig

logger = logging.getLogger(__name__)

# Table properties applied on creation and preserved on merge
_TABLE_PROPERTIES = {
    "delta.enableChangeDataFeed":        "true",
    "delta.autoOptimize.optimizeWrite":  "true",
    "delta.autoOptimize.autoCompact":    "true",
}


def upsert_to_raw(
    spark: SparkSession,
    df: DataFrame,
    cfg: EntityConfig,
    catalog: str,
    raw_schema: str,
) -> Dict[str, Any]:
    """Merge *df* into the raw Delta table for *cfg*.

    Returns a metrics dict with either ``{"operation": "create"}`` or
    ``{"operation": "merge", "metrics": {...}}`` from Delta history.
    """
    fqn = f"`{catalog}`.`{raw_schema}`.`{cfg.source}_{cfg.entity}`"
    plain_fqn = f"{catalog}.{raw_schema}.{cfg.source}_{cfg.entity}"

    merge_cond = " AND ".join(
        f"target.`{k}` = source.`{k}`" for k in cfg.primary_keys
    )

    # ── Deduplicate source: keep latest record per primary key ────────────────
    w = Window.partitionBy(*[F.col(k) for k in cfg.primary_keys]) \
              .orderBy(F.col(cfg.sequence_by).desc())
    df = df.withColumn("_rn", F.row_number().over(w)) \
           .filter("_rn = 1") \
           .drop("_rn")

    # ── Create on first run ───────────────────────────────────────────────────
    if not spark.catalog.tableExists(plain_fqn):
        logger.info("Creating Delta table %s", fqn)
        writer = df.writeTo(fqn).using("delta")
        for prop, val in _TABLE_PROPERTIES.items():
            writer = writer.tableProperty(prop, val)
        writer = writer.tableProperty("quality", "raw")
        writer = writer.tableProperty("source_system", cfg.source)
        writer = writer.tableProperty("entity", cfg.entity)
        writer.create()
        return {"operation": "create"}

    # ── Merge on subsequent runs ──────────────────────────────────────────────
    logger.info("Merging into %s on keys %s", fqn, cfg.primary_keys)
    delta_tbl = DeltaTable.forName(spark, plain_fqn)
    merge = delta_tbl.alias("target").merge(df.alias("source"), merge_cond)

    if cfg.sequence_by != "_ingestion_timestamp":
        # Only overwrite when the incoming record is not older
        merge = merge.whenMatchedUpdateAll(
            condition=f"source.`{cfg.sequence_by}` >= target.`{cfg.sequence_by}`"
        )
    else:
        merge = merge.whenMatchedUpdateAll()

    merge.whenNotMatchedInsertAll().execute()

    history = delta_tbl.history(1).select("operationMetrics").collect()
    metrics = dict(history[0]["operationMetrics"]) if history else {}
    return {"operation": "merge", "metrics": metrics}
