from datetime import datetime

from airflow.sdk import DAG
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator

with DAG(
    dag_id="test_snowflake_connection",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
):

    SQLExecuteQueryOperator(
        task_id="test_snowflake",
        conn_id="opentrends_snowflake",
        sql="""
            SELECT
                CURRENT_USER(),
                CURRENT_ROLE(),
                CURRENT_WAREHOUSE(),
                CURRENT_DATABASE();
        """,
    )
