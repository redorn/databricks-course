"""
Entity configurations for the IO Lakehouse raw ingestion pipeline.

Each EntityConfig describes one landing-zone dataset:
  - where to find the files  (source + entity → S3 path)
  - how to parse them        (file_format, separator, header)
  - how to upsert into Raw   (primary_keys, sequence_by)

Naming conventions
------------------
  Landing DLT table : lnd_{source}_{entity}
  Raw Delta table   : {source}_{entity}
  Default S3 path   : {s3_landing_base}/{source}/{entity}/

To add a new entity, append an EntityConfig to ENTITY_CONFIGS below.
No other file needs to change.
"""

from dataclasses import dataclass
from typing import List, Optional


@dataclass
class EntityConfig:
    # ── Identity ──────────────────────────────────────────────────────────────
    source: str       # Source system label  (e.g. "gizmobox")
    entity: str       # Entity / table name   (e.g. "customers")

    # ── File format ───────────────────────────────────────────────────────────
    file_format: str  # Spark/Auto Loader format: json | csv | binaryFile
    primary_keys: List[str]
    sequence_by: str  # Column used to order events for upsert.
                      # Use "_ingestion_timestamp" when no natural timestamp exists.

    # ── Optional overrides ────────────────────────────────────────────────────
    separator: Optional[str] = None   # Field delimiter for CSV/TSV (e.g. "\t")
    header: bool = True               # Whether file has a header row
    multiline: bool = False           # True for multi-line JSON records
    path_suffix: Optional[str] = None # Override sub-path under S3 landing root
    columns: Optional[List[str]] = None  # Column names for headerless CSVs

    # ── Derived names ─────────────────────────────────────────────────────────
    @property
    def landing_table(self) -> str:
        return f"lnd_{self.source}_{self.entity}"

    @property
    def raw_table(self) -> str:
        return f"{self.source}_{self.entity}"

    def landing_path(self, s3_base: str) -> str:
        suffix = self.path_suffix or f"{self.source}/{self.entity}/"
        return f"{s3_base.rstrip('/')}/{suffix}"

    def schema_location(self, s3_base: str) -> str:
        """Auto Loader schema checkpoint location (used in DLT pipeline)."""
        return f"{s3_base.rstrip('/')}/_schemas/{self.source}/{self.entity}"


# ── Entity registry ────────────────────────────────────────────────────────────
ENTITY_CONFIGS: List[EntityConfig] = [

    # ── GIZMOBOX ──────────────────────────────────────────────────────────────
    EntityConfig(
        source="gizmobox",
        entity="customers",
        file_format="json",
        primary_keys=["customer_id"],
        sequence_by="created_timestamp",
    ),
    EntityConfig(
        source="gizmobox",
        entity="addresses",
        file_format="csv",
        separator="\t",              # TSV
        primary_keys=["customer_id", "address_type"],
        sequence_by="_ingestion_timestamp",
    ),
    EntityConfig(
        source="gizmobox",
        entity="orders",
        file_format="json",
        primary_keys=["order_id"],
        sequence_by="transaction_timestamp",
    ),
    EntityConfig(
        source="gizmobox",
        entity="payments",
        file_format="csv",
        header=False,
        primary_keys=["payment_id"],
        sequence_by="payment_timestamp",
        columns=["payment_id", "order_id", "payment_timestamp", "amount", "payment_method"],
    ),
    # gizmobox/memberships – skipped for now (binary PNG data not yet uploaded)
    # gizmobox/refunds    – skipped (Azure SQL via JDBC, ingested separately)

    # ── CIRCUITBOX ────────────────────────────────────────────────────────────
    EntityConfig(
        source="circuitbox",
        entity="customers",
        file_format="json",
        primary_keys=["customer_id"],
        sequence_by="created_date",
    ),
    EntityConfig(
        source="circuitbox",
        entity="addresses",
        file_format="csv",
        primary_keys=["customer_id"],
        sequence_by="created_date",
    ),
    EntityConfig(
        source="circuitbox",
        entity="orders",
        file_format="json",
        primary_keys=["order_id"],
        sequence_by="order_timestamp",
    ),

    # ── MARKET / REFERENCE ────────────────────────────────────────────────────
    EntityConfig(
        source="market",
        entity="stock_prices",
        file_format="json",
        primary_keys=["stock_id", "trading_date"],
        sequence_by="trading_date",
        path_suffix="stock_prices/",           # flat folder, no source sub-dir
    ),
    EntityConfig(
        source="market",
        entity="top_tech_companies",
        file_format="csv",
        primary_keys=["company_name"],
        sequence_by="_ingestion_timestamp",
        path_suffix="top_tech_companies/",
    ),
]
