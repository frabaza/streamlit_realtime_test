import time
import streamlit as st
from google.cloud import bigquery

# 1. Initialize session state for auto-refresh toggle.
if "auto_refresh" not in st.session_state:
    st.session_state["auto_refresh"] = False

def run_dashboard():
    st.title("Ethereum Blocks Real-Time (Demo)")

    # 2. Toggle button for auto-refresh
    if st.button("Toggle Auto Refresh"):
        st.session_state["auto_refresh"] = not st.session_state["auto_refresh"]

    st.write(f"Auto Refresh is currently: **{st.session_state['auto_refresh']}**")

    # 3. BigQuery query to see how many blocks mined today vs last hour
    client = bigquery.Client(project="telegram-bot-361314")

    query = """
    WITH blocks_today AS (
      SELECT COUNT(*) AS count
      FROM `bigquery-public-data.crypto_ethereum.blocks`
      WHERE DATE(timestamp) = CURRENT_DATE()
    ),
    blocks_last_hour AS (
      SELECT COUNT(*) AS count
      FROM `bigquery-public-data.crypto_ethereum.blocks`
      WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
    )
    SELECT
      (SELECT count FROM blocks_today) AS blocks_today,
      (SELECT count FROM blocks_last_hour) AS blocks_last_hour
    """

    query_job = client.query(query)
    results = query_job.result().to_dataframe()

    blocks_today = results["blocks_today"][0]
    blocks_hour = results["blocks_last_hour"][0]

    # Show metrics
    st.metric(label="Blocks Mined Today", value=blocks_today)
    st.metric(label="Blocks in Last Hour", value=blocks_hour)

    # 4. Optional chart: blocks per hour in the last 24 hours
    hour_query = """
    SELECT
      TIMESTAMP_TRUNC(timestamp, HOUR) AS hour,
      COUNT(*) AS blocks_count
    FROM `bigquery-public-data.crypto_ethereum.blocks`
    WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
    GROUP BY hour
    ORDER BY hour
    """

    hour_query_job = client.query(hour_query)
    hour_results = hour_query_job.result().to_dataframe()
    st.subheader("Blocks per hour (last 24 hours)")
    st.line_chart(
        data=hour_results,
        x="hour",
        y="blocks_count",
    )

    # 5. If auto-refresh is ON, sleep 10s then rerun
    if st.session_state["auto_refresh"]:
        time.sleep(10)  # refresh interval
        st.rerun()

if __name__ == "__main__":
    run_dashboard()
