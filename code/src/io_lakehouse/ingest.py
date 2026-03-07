"""Orchestration layer: iterate over entity configs and run read → upsert."""

import logging

from pyspark.sql import SparkSession

from io_lakehouse.entity_config import ENTITY_CONFIGS
from io_lakehouse.reader import read_landing
from io_lakehouse.writer import upsert_to_raw

logger = logging.getLogger(__name__)


def run_ingestion(
    spark: SparkSession,
    catalog: str,
    raw_schema: str,
    s3_landing_path: str,
    source_filter: str = "",
    entity_filter: str = "",
) -> None:
    """Run batch ingestion for all (or filtered) entities.

    Args:
        spark:           Active SparkSession.
        catalog:         Unity Catalog name (e.g. "io_lakehouse_dev").
        raw_schema:      Target schema for raw Delta tables (e.g. "raw").
        s3_landing_path: S3 root of the landing zone (e.g. "s3://bucket/landing").
        source_filter:   Restrict to a single source system; empty = all.
        entity_filter:   Restrict to a single entity; empty = all.
    """
    configs = [
        cfg for cfg in ENTITY_CONFIGS
        if (not source_filter or cfg.source == source_filter)
        and (not entity_filter or cfg.entity == entity_filter)
    ]

    if not configs:
        available = ", ".join(f"{c.source}/{c.entity}" for c in ENTITY_CONFIGS)
        raise ValueError(
            f"No entity matched source_filter={source_filter!r}, "
            f"entity_filter={entity_filter!r}. Available: {available}"
        )

    logger.info("Starting ingestion: %d entity(ies)", len(configs))
    errors = []

    for cfg in configs:
        label = f"{cfg.source}/{cfg.entity}"
        try:
            logger.info("[%s] Reading from %s", label, cfg.landing_path(s3_landing_path))
            df = read_landing(spark, cfg, s3_landing_path)
            result = upsert_to_raw(spark, df, cfg, catalog, raw_schema)
            logger.info("[%s] Done – %s", label, result)
        except Exception as exc:
            logger.error("[%s] FAILED: %s", label, exc, exc_info=True)
            errors.append(label)

    if errors:
        raise RuntimeError(f"Ingestion failed for: {errors}")

    logger.info("Ingestion complete – %d entity(ies) processed.", len(configs))
