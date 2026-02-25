"""
DAG: CoinGecko Market Data -> S3 Raw

Fetches cryptocurrency market data from the CoinGecko API and saves it to S3 as JSON.
Pagination is used to retrieve 200+ coins per run (2 pages x 100 coins).

Schedule: Every 5 minutes
Target: s3://<BUCKET>/raw/source=coingecko/dataset=coins_markets/date=YYYY-MM-DD/hour=HH/
"""

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

# Pagination: coins per page (CoinGecko max 250/page)
COINS_PER_PAGE = 100
TOTAL_PAGES = 2  # 2 pages x 100 = 200 coins

default_args = {
    "owner": "airflow",
    "start_date": days_ago(1),
    "retries": 2,
}

with DAG(
    dag_id="coingecko_coins_markets_s3_raw",
    default_args=default_args,
    schedule_interval="*/5 * * * *",
    catchup=False,
    tags=["crypto", "coingecko", "s3", "raw"],
) as dag:

    @task()
    def extract_coins_markets():
        """
        Fetches market data from the CoinGecko API.
        Multiple pages are retrieved via pagination.
        """
        http_hook = HttpHook(http_conn_id=API_CONN_ID, method="GET")
        endpoint = "/api/v3/coins/markets"
        processed_at = datetime.now(timezone.utc).isoformat()

        all_coins = []

        for page in range(1, TOTAL_PAGES + 1):
            params = {
                "vs_currency": "usd",
                "order": "market_cap_desc",
                "per_page": COINS_PER_PAGE,
                "page": page,
                "sparkline": "false",
                "price_change_percentage": "1h,24h,7d",
            }

            response = http_hook.run(
                endpoint,
                data=params,
                extra_options={"timeout": 30},
            )

            if response.status_code != 200:
                raise Exception(
                    f"CoinGecko API failed: page={page} status={response.status_code} "
                    f"body={response.text[:200]}"
                )

            page_data = response.json()

            if not page_data:
                logging.info("Page %d returned empty, stopping pagination.", page)
                break

            all_coins.extend(page_data)
            logging.info("Page %d: fetched %d coins.", page, len(page_data))

        if not all_coins:
            raise AirflowSkipException("CoinGecko returned empty data; skipping S3 upload.")

        for coin in all_coins:
            coin["processed_at"] = processed_at
            coin["source"] = SOURCE
            coin["dataset"] = DATASET

        logging.info(
            "Total fetched: %d coins from %d pages. processed_at=%s",
            len(all_coins), TOTAL_PAGES, processed_at,
        )
        return all_coins

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

        logging.info("Uploaded %d records to s3://%s/%s", len(records), BUCKET_NAME, key)
        return {"s3_bucket": BUCKET_NAME, "s3_key": key, "record_count": len(records)}

    # DAG task flow
    coins_data = extract_coins_markets()
    s3_result = upload_raw_to_s3(coins_data)
