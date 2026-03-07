"""CLI entry point for the io-lakehouse-ingest wheel task.

Invoked by the Databricks python_wheel_task via the console-script
entry point defined in pyproject.toml:

    io-lakehouse-ingest = "io_lakehouse.main:main"

Databricks passes job task parameters as named_parameters which arrive
as ``--key value`` arguments to this script.

Examples
--------
# Full run (all entities):
io-lakehouse-ingest \\
    --catalog io_lakehouse_dev \\
    --s3-landing-path s3://io-lakehouse-landing/raw \\
    --raw-schema raw

# Setup + single entity:
io-lakehouse-ingest \\
    --catalog io_lakehouse_dev \\
    --s3-landing-path s3://io-lakehouse-landing/raw \\
    --run-setup true \\
    --source-filter gizmobox \\
    --entity-filter customers
"""

import argparse
import logging

from pyspark.sql import SparkSession

from io_lakehouse.ingest import run_ingestion
from io_lakehouse.setup import run_setup

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s – %(message)s",
)


def _parse_args():
    p = argparse.ArgumentParser(description="IO Lakehouse batch ingestion")
    p.add_argument("--catalog",           required=True,  help="Unity Catalog name")
    p.add_argument("--s3-landing-path",   required=True,  dest="s3_landing_path",
                   help="S3 root of the landing zone (e.g. s3://bucket/landing)")
    p.add_argument("--raw-schema",        default="raw",     dest="raw_schema")
    p.add_argument("--landing-schema",    default="landing", dest="landing_schema")
    p.add_argument("--source-filter",     default="",        dest="source_filter",
                   help="Restrict to a single source system (empty = all)")
    p.add_argument("--entity-filter",     default="",        dest="entity_filter",
                   help="Restrict to a single entity (empty = all)")
    p.add_argument("--run-setup",         default="false",   dest="run_setup",
                   help="'true' to create schemas and external tables before ingestion")
    return p.parse_args()


def main():
    args = _parse_args()
    spark = SparkSession.getActiveSession() or SparkSession.builder.getOrCreate()

    if args.run_setup.lower() == "true":
        run_setup(
            spark=spark,
            catalog=args.catalog,
            landing_schema=args.landing_schema,
            s3_landing_path=args.s3_landing_path,
            source_filter=args.source_filter,
        )

    run_ingestion(
        spark=spark,
        catalog=args.catalog,
        raw_schema=args.raw_schema,
        s3_landing_path=args.s3_landing_path,
        source_filter=args.source_filter,
        entity_filter=args.entity_filter,
    )


if __name__ == "__main__":
    main()
