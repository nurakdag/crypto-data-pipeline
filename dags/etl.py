from airflow import DAG
from airflow.providers.http.hooks.http import HttpHook
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.decorators import task
from airflow.utils.dates import days_ago
from airflow.exceptions import AirflowSkipException

import json
import logging
from datetime import datetime, timezone

# Airflow connection IDs
API_CONN_ID = "coingecko_api"
S3_CONN_ID = "s3_conn"

# Constants
BUCKET_NAME = "crypto-data-pipeline-raw-dev"
SOURCE = "coingecko"
DATASET = "coins_markets"

default_args = {
    "owner": "airflow",
    "start_date": days_ago(1),
    "retries": 2,
}

with DAG(
    dag_id="coingecko_trending_coins_s3_raw",
    default_args=default_args,
    schedule_interval="*/5 * * * *",
    catchup=False,
    tags=["crypto", "coingecko", "s3", "raw"],
) as dag:

    @task()
    def extract_trending_coins():
        """Fetches market data from the CoinGecko API."""
        http_hook = HttpHook(http_conn_id=API_CONN_ID, method="GET")

        endpoint = "/api/v3/coins/markets"
        params = {
            "vs_currency": "usd",
            "order": "volume_desc",
            "per_page": 10,
            "page": 1,
        }

        processed_at = datetime.now(timezone.utc).isoformat()


        response = http_hook.run(
            endpoint,
            data=params,
            extra_options={"timeout": 30},
        )

        if response.status_code != 200:
            raise Exception(
                f"CoinGecko API failed: status={response.status_code} body={response.text[:200]}"
            )

        data = response.json()

        if not data:
            raise AirflowSkipException("CoinGecko returned empty data; skipping S3 upload.")

        for coin in data:
            coin["processed_at"] = processed_at
            coin["source"] = SOURCE
            coin["dataset"] = DATASET

        logging.info("Fetched %s records from CoinGecko. processed_at=%s", len(data), processed_at)
        return data

    @task()
    def upload_raw_to_s3(records):
        """
        Upload raw data to S3 with partitioned key structure.
        Raw zone should be immutable -> replace=False.
        """
        s3_hook = S3Hook(aws_conn_id=S3_CONN_ID)

        now = datetime.now(timezone.utc)
        date_part = now.strftime("%Y-%m-%d")
        hour_part = now.strftime("%H")
        ts = now.strftime("%Y%m%dT%H%M%SZ")

        key = (
            f"raw/source={SOURCE}/dataset={DATASET}/date={date_part}/hour={hour_part}/"
            f"data_{ts}.json"
        )

        json_data = json.dumps(records, ensure_ascii=False)

        s3_hook.load_string(
            string_data=json_data,
            key=key,
            bucket_name=BUCKET_NAME,
            replace=False,  
        )

        logging.info("Uploaded raw data to s3://%s/%s", BUCKET_NAME, key)
        return {"s3_bucket": BUCKET_NAME, "s3_key": key, "record_count": len(records)}

    # DAG task flow
    trending_coins_data = extract_trending_coins()
    s3_upload_info = upload_raw_to_s3(trending_coins_data)
