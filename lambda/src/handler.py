"""
Lambda: Raw JSON -> Processed Parquet

S3'e raw JSON dosyasi dustugunde tetiklenir.
JSON'u okur, pandas DataFrame'e cevirir, Parquet olarak processed bucket'a yazar.

Tetikleme: S3 Event Notification (PutObject on raw/ prefix)
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

# Env variable olarak Terraform'dan inject edilecek
PROCESSED_BUCKET = os.environ["PROCESSED_BUCKET"]


def handler(event, context):
    """
    S3 event'inden gelen her record icin:
    1. Raw JSON dosyasini S3'ten oku
    2. pandas DataFrame'e cevir
    3. Parquet olarak processed bucket'a yaz

    S3 key ornek:
      raw/source=coingecko/dataset=coins_markets/date=2026-01-31/hour=14/data_20260131T140500Z.json
    Processed key ornek:
      processed/source=coingecko/dataset=coins_markets/date=2026-01-31/hour=14/data_20260131T140500Z.parquet
    """
    for record in event["Records"]:
        source_bucket = record["s3"]["bucket"]["name"]
        source_key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        logger.info("Processing: s3://%s/%s", source_bucket, source_key)

        # 1. Raw JSON'u oku
        # utf-8-sig: BOM (Byte Order Mark) varsa otomatik siler.
        # BOM olmayan dosyalarda da sorunsuz calisir.
        response = s3_client.get_object(Bucket=source_bucket, Key=source_key)
        raw_body = response["Body"].read().decode("utf-8-sig")
        data = json.loads(raw_body)

        if not data:
            logger.warning("Empty data in %s, skipping.", source_key)
            continue

        # 2. DataFrame'e cevir
        df = pd.json_normalize(data)

        logger.info(
            "Converted %d records, %d columns. Columns: %s",
            len(df),
            len(df.columns),
            list(df.columns),
        )

        # 3. Parquet key'ini olustur: raw/ -> processed/, .json -> .parquet
        processed_key = source_key.replace("raw/", "processed/", 1).replace(
            ".json", ".parquet"
        )

        # 4. Parquet olarak yaz (in-memory buffer)
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
