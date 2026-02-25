"""
Lambda: Raw JSON -> Processed Parquet

Triggered when a raw JSON file lands in S3.
Reads the JSON, converts it to a pandas DataFrame, and writes it as Parquet
to the processed bucket.

Trigger: S3 Event Notification (PutObject on raw/ prefix)
"""

import json
import logging
import os
import urllib.parse

import boto3
import pandas as pd

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client("s3")

# Injected by Terraform as a Lambda environment variable
PROCESSED_BUCKET = os.environ["PROCESSED_BUCKET"]


def handler(event, context):
    """
    For each S3 record in the event:
    1. Read the raw JSON file from S3
    2. Convert to a pandas DataFrame
    3. Write as Parquet to the processed bucket

    Example S3 key (raw):
      raw/source=coingecko/dataset=coins_markets/date=2026-01-31/hour=14/data_20260131T140500Z.json
    Example S3 key (processed):
      processed/source=coingecko/dataset=coins_markets/date=2026-01-31/hour=14/data_20260131T140500Z.parquet
    """
    for record in event["Records"]:
        source_bucket = record["s3"]["bucket"]["name"]
        source_key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        logger.info("Processing: s3://%s/%s", source_bucket, source_key)

        # 1. Read raw JSON from S3
        # utf-8-sig strips a leading BOM (Byte Order Mark) if present;
        # files without a BOM are decoded correctly as well.
        response = s3_client.get_object(Bucket=source_bucket, Key=source_key)
        raw_body = response["Body"].read().decode("utf-8-sig")
        data = json.loads(raw_body)

        if not data:
            logger.warning("Empty data in %s, skipping.", source_key)
            continue

        # 2. Convert to DataFrame
        df = pd.json_normalize(data)

        # Cast integer columns to float so Parquet stores them as DOUBLE.
        # Without this, pandas writes INT64 which conflicts with the DOUBLE
        # type declared in the Glue table schema, causing Athena query errors.
        int_cols = df.select_dtypes(include=["int64", "int32"]).columns
        if len(int_cols) > 0:
            df[int_cols] = df[int_cols].astype(float)
            logger.info("Cast %d integer columns to float: %s", len(int_cols), list(int_cols))

        logger.info(
            "Converted %d records, %d columns. Columns: %s",
            len(df),
            len(df.columns),
            list(df.columns),
        )

        # 3. Derive processed key: replace raw/ prefix and .json extension
        processed_key = source_key.replace("raw/", "processed/", 1).replace(
            ".json", ".parquet"
        )

        # 4. Serialize to Parquet in memory and upload
        parquet_buffer = df.to_parquet(index=False)

        s3_client.put_object(
            Bucket=PROCESSED_BUCKET,
            Key=processed_key,
            Body=parquet_buffer,
            ContentType="application/octet-stream",
        )

        logger.info(
            "Wrote parquet: s3://%s/%s (%d bytes)",
            PROCESSED_BUCKET,
            processed_key,
            len(parquet_buffer),
        )

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Processing complete"}),
    }
