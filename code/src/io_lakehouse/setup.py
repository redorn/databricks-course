"""One-time (idempotent) setup: create Unity Catalog schemas and landing external tables.

Called by the parameterized job when --run-setup true is passed.
All statements use IF NOT EXISTS so re-runs are safe.
"""

import logging

from pyspark.sql import SparkSession

from io_lakehouse.entity_config import ENTITY_CONFIGS

logger = logging.getLogger(__name__)

# Entities that have structured landing files (skip binaryFile memberships)
_STRUCTURED = [cfg for cfg in ENTITY_CONFIGS if cfg.file_format != "binaryFile"]


def _options_clause(cfg) -> str:
    opts = {}
    if cfg.file_format == "csv":
        opts["header"] = "true"
        if cfg.separator:
            opts["sep"] = cfg.separator
    return (
        "OPTIONS (" + ", ".join(f"'{k}'='{v}'" for k, v in opts.items()) + ")"
        if opts else ""
    )


def run_setup(
    spark: SparkSession,
    catalog: str,
    landing_schema: str,
    s3_landing_path: str,
    source_filter: str = "",
) -> None:
    """Create schemas and external landing tables.

    Args:
        spark:           Active SparkSession.
        catalog:         Unity Catalog name.
        landing_schema:  Schema for external tables (e.g. "landing").
        s3_landing_path: S3 root of the landing zone.
        source_filter:   Restrict table creation to one source; empty = all.
    """
    base = s3_landing_path.rstrip("/")

    logger.info("Creating schemas in catalog '%s'", catalog)
    spark.sql(
        f"CREATE SCHEMA IF NOT EXISTS `{catalog}`.`{landing_schema}` "
        f"COMMENT 'External tables on the S3 landing zone'"
    )
    spark.sql(
        f"CREATE SCHEMA IF NOT EXISTS `{catalog}`.`raw` "
        f"COMMENT 'Raw Delta tables – upserted from the landing zone'"
    )

    # External tables require a cloud storage scheme (s3://, abfss://, gs://).
    # UC Volume paths (/Volumes/...) don't support CREATE EXTERNAL TABLE —
    # the batch job reads directly from the Volume via spark.read instead.
    if base.startswith("/Volumes"):
        logger.info(
            "Landing path is a UC Volume (%s) – skipping external table "
            "creation (spark.read will access files directly).", base,
        )
        logger.info("Setup complete – schemas created, external tables skipped.")
        return

    configs = [
        cfg for cfg in _STRUCTURED
        if not source_filter or cfg.source == source_filter
    ]

    for cfg in configs:
        table_fqn = f"`{catalog}`.`{landing_schema}`.`{cfg.source}_{cfg.entity}`"
        location  = cfg.landing_path(base)
        fmt       = cfg.file_format.upper()
        options   = _options_clause(cfg)

        ddl = (
            f"CREATE EXTERNAL TABLE IF NOT EXISTS {table_fqn} "
            f"USING {fmt} "
            f"{options} "
            f"LOCATION '{location}'"
        )
        logger.info("  %s → %s", table_fqn, location)
        spark.sql(ddl)

    logger.info("Setup complete – %d external table(s) registered.", len(configs))
