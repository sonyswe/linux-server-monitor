
import streamlit as st
import pandas as pd
from pathlib import Path

# ==========================================
# PAGE CONFIGURATION
# ==========================================

st.set_page_config(
    page_title="Linux Server Monitor",
    page_icon="🖥️",
    layout="wide"
)

BASE_DIR = Path(__file__).resolve().parent
CSV_FILE = BASE_DIR / "data" / "metrics.csv"

st.title("🖥️ Linux Server Monitoring Dashboard")
st.caption("Real-time server health overview and historical metrics")

# ==========================================
# LOAD METRICS
# ==========================================

@st.cache_data(ttl=30)
def load_metrics():
    if not CSV_FILE.exists():
        return pd.DataFrame()

    df = pd.read_csv(CSV_FILE)

    if df.empty or "timestamp" not in df.columns:
        return pd.DataFrame()

    df["timestamp"] = pd.to_datetime(
        df["timestamp"],
        errors="coerce"
    )

    df = df.dropna(subset=["timestamp"])
    df = df.sort_values("timestamp")

    return df


if st.button("🔄 Refresh Dashboard"):
    st.cache_data.clear()
    st.rerun()

df = load_metrics()

if df.empty:
    st.warning("No monitoring data available. Run monitor.sh first.")
    st.stop()

# ==========================================
# LATEST METRICS
# ==========================================

latest = df.iloc[-1]

st.subheader("Latest Server Metrics")

col1, col2, col3 = st.columns(3)

col1.metric(
    "CPU Usage",
    f"{latest['cpu']}%"
)

col2.metric(
    "Memory Usage",
    f"{latest['memory']}%"
)

col3.metric(
    "Root Disk Usage",
    f"{latest['root_disk']}%"
)

st.caption(
    f"Last updated: {latest['timestamp']}"
)

# ==========================================
# DISK USAGE
# ==========================================

st.subheader("Disk Usage Overview")

disk_col1, disk_col2, disk_col3 = st.columns(3)

disk_col1.metric("Root (/)", f"{latest['root_disk']}%")
disk_col2.metric("Windows C: (/mnt/c)", f"{latest['mnt_c_disk']}%")
disk_col3.metric("Windows D: (/mnt/d)", f"{latest['mnt_d_disk']}%")

# ==========================================
# SERVICE STATUS
# ==========================================

st.subheader("Monitored Services")

service_col1, service_col2 = st.columns(2)

def show_service(column, name, status):
    if status == "RUNNING":
        column.success(f"{name}: RUNNING")
    else:
        column.error(f"{name}: {status}")

show_service(service_col1, "SSH", latest["ssh_status"])
show_service(service_col2, "Nginx", latest["nginx_status"])

# ==========================================
# HISTORICAL CPU AND MEMORY
# ==========================================

st.subheader("CPU and Memory History")

history = df.set_index("timestamp")

st.line_chart(
    history[["cpu", "memory"]],
    y_label="Usage (%)"
)

# ==========================================
# HISTORICAL DISK USAGE
# ==========================================

st.subheader("Disk Usage History")

st.line_chart(
    history[["root_disk", "mnt_c_disk", "mnt_d_disk"]],
    y_label="Disk Usage (%)"
)

# ==========================================
# RAW METRICS
# ==========================================

with st.expander("View Historical Monitoring Records"):
    st.dataframe(
        df.sort_values("timestamp", ascending=False),
        use_container_width=True,
        hide_index=True
    )

st.caption("Data source: data/metrics.csv")
