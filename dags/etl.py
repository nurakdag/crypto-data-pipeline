from airflow import DAG
from airflow.providers.http.hooks.http import HttpHook
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.decorators import task
from airflow.utils.dates import days_ago
import json
from datetime import datetime

# Airflow connection IDs
POSTGRES_CONN_ID = 'postgres_default'
API_CONN_ID = 'coingecko_api'
S3_CONN_ID = 's3_conn'  

default_args = {
    'owner': 'airflow',
    'start_date': days_ago(1),
    'retries': 1,
}

# DAG Definition
with DAG(
    dag_id='coingecko_trending_coins_s3_raw',
    default_args=default_args,
    schedule_interval='*/5 * * * *', 
    catchup=False
) as dag:
    
    @task()
    def extract_trending_coins():
        """Fetches trending coins from the CoinGecko API."""
        http_hook = HttpHook(http_conn_id=API_CONN_ID, method='GET')
        
        # CoinGecko API endpoint and parameters
        endpoint = '/api/v3/coins/markets'
        params = {
            "vs_currency": "usd",
            "order": "volume_desc",
            "per_page": 10,
            "page": 1
        }
        
        # API call
        response = http_hook.run(endpoint, data=params)
        if response.status_code == 200:
            return response.json()
        else:
            raise Exception(f"Failed to fetch data from API: {response.status_code}")
    
    @task()
    def upload_raw_to_s3(data_trending_coins):
        """Raw verileri S3'e yükler."""
        # S3 Hook oluştur
        s3_hook = S3Hook(aws_conn_id=S3_CONN_ID)
        
        # Dosya adı için timestamp ekle
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        key = f'raw/coingecko_trending_coins_{timestamp}.json'
        
        # JSON verisini string'e dönüştür
        json_data = json.dumps(data_trending_coins)
        
        # S3'e yükle
        bucket_name = 'rawcryptodata'  # S3 bucket adınızı buraya girin
        s3_hook.load_string(
            string_data=json_data,
            key=key,
            bucket_name=bucket_name,
            replace=True
        )
        
        return {'s3_bucket': bucket_name, 's3_key': key}
    
    
    
    
    # DAG task flow
    trending_coins_data = extract_trending_coins()
    s3_upload_info = upload_raw_to_s3(trending_coins_data)
    
    