import streamlit as st
import pandas as pd
from pathlib import Path

st.set_page_config(
    page_title="Linux Server Monitor",
    page_icon="🖥️",
    layout="wide"
)

BASE_DIR = Path(__file__).resolve().parent
REAL_CSV = BASE_DIR / "data" / "metrics.csv"
DEMO_CSV = BASE_DIR / "data" / "demo_metrics.csv"

st.title("🖥️ Linux Server Monitoring Dashboard")
st.caption("Server health overview and historical monitoring metrics")


@st.cache_data(ttl=30)
def load_metrics():
    # Prefer actual monitoring data when available.
    if REAL_CSV.exists() and REAL_CSV.stat().st_size > 0:
        csv_file = REAL_CSV
        demo_mode = False
    else:
        csv_file = DEMO_CSV
        demo_mode = True

    if not csv_file.exists():
        return pd.DataFrame(), demo_mode

    df = pd.read_csv(csv_file)

    required_columns = [
        "timestamp", "cpu", "memory", "root_disk",
        "mnt_c_disk", "mnt_d_disk",
        "ssh_status", "nginx_status"
    ]

    if df.empty or not all(col in df.columns for col in required_columns):
        return pd.DataFrame(), demo_mode

    df["timestamp"] = pd.to_datetime(
        df["timestamp"], errors="coerce"
    )

    df = df.dropna(subset=["timestamp"])
    df = df.sort_values("timestamp")

    return df, demo_mode


if st.button("🔄 Refresh Dashboard"):
    st.cache_data.clear()
    st.rerun()

df, demo_mode = load_metrics()

if df.empty:
    st.warning("No valid monitoring data available.")
    st.stop()

if demo_mode:
    st.info("Demo mode: displaying sample monitoring data.")
else:
    st.success("Live local data: displaying metrics collected by monitor.sh.")

latest = df.iloc[-1]

st.subheader("Latest Server Metrics")

col1, col2, col3 = st.columns(3)

col1.metric("CPU Usage", f"{latest['cpu']}%")
col2.metric("Memory Usage", f"{latest['memory']}%")
col3.metric("Root Disk Usage", f"{latest['root_disk']}%")

st.caption(f"Last updated: {latest['timestamp']}")

st.subheader("Disk Usage Overview")

disk_col1, disk_col2, disk_col3 = st.columns(3)

disk_col1.metric("Root (/)", f"{latest['root_disk']}%")
disk_col2.metric("Windows C: (/mnt/c)", f"{latest['mnt_c_disk']}%")
disk_col3.metric("Windows D: (/mnt/d)", f"{latest['mnt_d_disk']}%")

st.subheader("Monitored Services")

service_col1, service_col2 = st.columns(2)


def show_service(column, name, status):
    if status == "RUNNING":
        column.success(f"{name}: RUNNING")
    else:
        column.error(f"{name}: {status}")


show_service(service_col1, "SSH", latest["ssh_status"])
show_service(service_col2, "Nginx", latest["nginx_status"])

st.subheader("CPU and Memory History")

history = df.set_index("timestamp")

st.line_chart(
    history[["cpu", "memory"]],
    y_label="Usage (%)"
)

st.subheader("Disk Usage History")

st.line_chart(
    history[["root_disk", "mnt_c_disk", "mnt_d_disk"]],
    y_label="Disk Usage (%)"
)

with st.expander("View Historical Monitoring Records"):
    st.dataframe(
        df.sort_values("timestamp", ascending=False),
        use_container_width=True,
        hide_index=True
    )

st.caption("Data source: local metrics.csv or demo_metrics.csv")
