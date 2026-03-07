"""Batch file reader for the landing zone.

Supports json, csv (including TSV), and binaryFile formats.
Returns a DataFrame enriched with audit columns.
"""

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import StringType

from io_lakehouse.entity_config import EntityConfig


def read_landing(spark: SparkSession, cfg: EntityConfig, s3_base: str) -> DataFrame:
    """Read all files for *cfg* from the landing zone in batch mode.

    Audit columns added to every DataFrame:
      _source_file         – S3 URI of the originating file
      _ingestion_timestamp – Wall-clock time of this batch run
    """
    path = cfg.landing_path(s3_base)

    if cfg.file_format == "binaryFile":
        return (
            spark.read
            .format("binaryFile")
            .option("pathGlobFilter", "*.png")
            .option("recursiveFileLookup", "true")
            .load(path)
            # binaryFile schema: path, modificationTime, length, content
            .withColumn("_source_file", F.col("path").cast(StringType()))
            .withColumn("_ingestion_timestamp", F.current_timestamp())
        )

    reader = spark.read.option("inferSchema", "true")

    if cfg.file_format == "json":
        reader = reader.option("multiLine", str(cfg.multiline).lower())

    elif cfg.file_format == "csv":
        reader = reader.option("header", str(cfg.header).lower())
        if cfg.separator:
            reader = reader.option("sep", cfg.separator)

    df = reader.format(cfg.file_format).load(path)

    # Rename columns for headerless CSVs when column names are provided
    if cfg.columns and not cfg.header:
        for i, col_name in enumerate(cfg.columns):
            df = df.withColumnRenamed(f"_c{i}", col_name)

    return (
        df
        .withColumn("_source_file",
                    F.col("_metadata.file_path").cast(StringType()))
        .withColumn("_ingestion_timestamp", F.current_timestamp())
    )
