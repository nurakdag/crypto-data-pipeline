"""
Lambda handler unit tests.

Uses moto to mock S3 — no real AWS connection required.
Run with: pytest -v tests/lambda/

Note: "lambda" is a Python keyword, so handler.py is imported via importlib.
"""

import importlib
import json
import io
import sys

import pandas as pd
import pytest
from moto import mock_aws


def _import_handler():
    """Imports lambda/src/handler.py using importlib to avoid the 'lambda' keyword conflict."""
    spec = importlib.util.spec_from_file_location(
        "handler", "lambda/src/handler.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.handler


@mock_aws
def test_handler_success_coingecko(s3_client, sample_coingecko_data, sample_s3_event):
    """
    Happy path: CoinGecko JSON -> Parquet conversion.
    Expects a .parquet file written to the processed bucket.
    """
    raw_key = sample_s3_event["Records"][0]["s3"]["object"]["key"]
    s3_client.put_object(
        Bucket="test-raw-bucket",
        Key=raw_key,
        Body=json.dumps(sample_coingecko_data).encode("utf-8"),
    )

    handler = _import_handler()
    result = handler(sample_s3_event, None)

    assert result["statusCode"] == 200

    expected_key = raw_key.replace("raw/", "processed/", 1).replace(".json", ".parquet")
    response = s3_client.get_object(Bucket="test-processed-bucket", Key=expected_key)
    parquet_bytes = response["Body"].read()

    df = pd.read_parquet(io.BytesIO(parquet_bytes))
    assert len(df) == 2
    assert "bitcoin" in df["id"].values
    assert "ethereum" in df["id"].values



@mock_aws
def test_handler_empty_data(s3_client):
    """
    An empty JSON array should be skipped without raising an error.
    Nothing should be written to the processed bucket.
    """
    raw_key = "raw/source=coingecko/dataset=coins_markets/date=2026-02-23/hour=15/data_empty.json"

    s3_client.put_object(
        Bucket="test-raw-bucket",
        Key=raw_key,
        Body=json.dumps([]).encode("utf-8"),
    )

    event = {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": "test-raw-bucket"},
                    "object": {"key": raw_key},
                }
            }
        ]
    }

    handler = _import_handler()
    result = handler(event, None)
    assert result["statusCode"] == 200

    objects = s3_client.list_objects_v2(Bucket="test-processed-bucket")
    assert objects.get("KeyCount", 0) == 0


@mock_aws
def test_handler_bom_handling(s3_client, sample_coingecko_data, sample_s3_event):
    """
    JSON files with a leading BOM (Byte Order Mark) must be handled gracefully.
    PowerShell's Out-File adds a BOM by default, so Lambda must strip it.
    """
    raw_key = sample_s3_event["Records"][0]["s3"]["object"]["key"]

    bom_json = b"\xef\xbb\xbf" + json.dumps(sample_coingecko_data).encode("utf-8")

    s3_client.put_object(
        Bucket="test-raw-bucket",
        Key=raw_key,
        Body=bom_json,
    )

    handler = _import_handler()
    result = handler(sample_s3_event, None)
    assert result["statusCode"] == 200

    expected_key = raw_key.replace("raw/", "processed/", 1).replace(".json", ".parquet")
    response = s3_client.get_object(Bucket="test-processed-bucket", Key=expected_key)
    df = pd.read_parquet(io.BytesIO(response["Body"].read()))

    assert len(df) == 2


@mock_aws
def test_handler_numeric_types(s3_client):
    """
    Integer columns must be cast to float64 in the output Parquet file.
    This ensures compatibility with the DOUBLE type declared in the Glue table schema.
    """
    data = [
        {
            "id": "bitcoin",
            "symbol": "btc",
            "name": "Bitcoin",
            "current_price": 98500.0,
            "market_cap": 1950000000000,  # integer — must be cast to float64
            "total_volume": 45000000000,  # integer — must be cast to float64
            "processed_at": "2026-02-23T15:00:00+00:00",
        }
    ]

    raw_key = "raw/source=coingecko/dataset=coins_markets/date=2026-02-23/hour=15/data_int_test.json"

    s3_client.put_object(
        Bucket="test-raw-bucket",
        Key=raw_key,
        Body=json.dumps(data).encode("utf-8"),
    )

    event = {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": "test-raw-bucket"},
                    "object": {"key": raw_key},
                }
            }
        ]
    }

    handler = _import_handler()
    result = handler(event, None)
    assert result["statusCode"] == 200

    expected_key = raw_key.replace("raw/", "processed/", 1).replace(".json", ".parquet")
    response = s3_client.get_object(Bucket="test-processed-bucket", Key=expected_key)
    df = pd.read_parquet(io.BytesIO(response["Body"].read()))

    assert df["market_cap"].dtype == "float64"
    assert df["total_volume"].dtype == "float64"


@mock_aws
def test_parquet_key_generation(s3_client, sample_coingecko_data):
    """
    The raw/ prefix must become processed/ and .json must become .parquet.
    The rest of the path (partition key segments) must remain unchanged.
    """
    raw_key = "raw/source=coingecko/dataset=coins_markets/date=2026-02-23/hour=15/data_20260223T150000Z.json"
    expected_key = "processed/source=coingecko/dataset=coins_markets/date=2026-02-23/hour=15/data_20260223T150000Z.parquet"

    s3_client.put_object(
        Bucket="test-raw-bucket",
        Key=raw_key,
        Body=json.dumps(sample_coingecko_data).encode("utf-8"),
    )

    event = {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": "test-raw-bucket"},
                    "object": {"key": raw_key},
                }
            }
        ]
    }

    handler = _import_handler()
    handler(event, None)

    response = s3_client.get_object(Bucket="test-processed-bucket", Key=expected_key)
    assert response["ContentLength"] > 0
