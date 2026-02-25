"""
pytest fixtures for Lambda unit tests.

Creates mocked S3 buckets using moto — no real AWS connection required.
"""

import json
import os

import boto3
import pytest
from moto import mock_aws


@pytest.fixture
def aws_credentials():
    """Fake AWS credentials required by moto to intercept boto3 calls."""
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_SECURITY_TOKEN"] = "testing"
    os.environ["AWS_SESSION_TOKEN"] = "testing"
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"


@pytest.fixture
def s3_client(aws_credentials):
    """Mock S3 client with raw and processed buckets pre-created."""
    with mock_aws():
        s3 = boto3.client("s3", region_name="us-east-1")

        s3.create_bucket(Bucket="test-raw-bucket")
        s3.create_bucket(Bucket="test-processed-bucket")

        # Set the env var that handler.py reads at import time; restore after test
        previous = os.environ.get("PROCESSED_BUCKET")
        os.environ["PROCESSED_BUCKET"] = "test-processed-bucket"

        yield s3

        if previous is None:
            os.environ.pop("PROCESSED_BUCKET", None)
        else:
            os.environ["PROCESSED_BUCKET"] = previous


@pytest.fixture
def sample_coingecko_data():
    """Sample CoinGecko API response payload."""
    return [
        {
            "id": "bitcoin",
            "symbol": "btc",
            "name": "Bitcoin",
            "current_price": 98500.0,
            "market_cap": 1950000000000.0,
            "total_volume": 45000000000.0,
            "processed_at": "2026-02-23T15:00:00+00:00",
            "source": "coingecko",
            "dataset": "coins_markets",
        },
        {
            "id": "ethereum",
            "symbol": "eth",
            "name": "Ethereum",
            "current_price": 3200.0,
            "market_cap": 385000000000.0,
            "total_volume": 18000000000.0,
            "processed_at": "2026-02-23T15:00:00+00:00",
            "source": "coingecko",
            "dataset": "coins_markets",
        },
    ]


@pytest.fixture
def sample_s3_event():
    """Sample S3 PutObject event — the shape Lambda receives from S3 Event Notifications."""
    return {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": "test-raw-bucket"},
                    "object": {
                        "key": "raw/source=coingecko/dataset=coins_markets/date=2026-02-23/hour=15/data_20260223T150000Z.json"
                    },
                }
            }
        ]
    }
