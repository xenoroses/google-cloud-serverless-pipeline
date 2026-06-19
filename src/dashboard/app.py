import os
import streamlit as st
import pandas as pd
from google.cloud import bigquery
from google.auth.exceptions import DefaultCredentialsError

# Set Streamlit page configuration
st.set_page_config(
    page_title="Document Processing Pipeline Dashboard",
    page_icon="📄",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom Styling (Aesthetics)
st.markdown("""
    <style>
    .main-title {
        font-size: 3rem;
        font-weight: 700;
        background: linear-gradient(90deg, #1E3A8A 0%, #3B82F6 100%);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        margin-bottom: 2rem;
    }
    .metric-card {
        background-color: #F3F4F6;
        border-radius: 8px;
        padding: 1.5rem;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
    }
    </style>
""", unsafe_allow_html=True)

# Initialize BigQuery Client
@st.cache_resource
def get_bq_client():
    try:
        # Check if local credentials are provided, or fall back to mock
        if not os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") and not os.environ.get("K_SERVICE"):
            return None
        return bigquery.Client()
    except DefaultCredentialsError:
        return None

bq_client = get_bq_client()

# Generate Mock Data for Local Testing
def get_mock_data():
    mock_records = [
        {"filename": "invoice_1024.pdf", "upload_time": "2026-06-19 10:15:30 UTC", "tags": ["pdf", "document", "invoice"], "word_count": 1250},
        {"filename": "store_receipt.png", "upload_time": "2026-06-19 11:20:45 UTC", "tags": ["image", "scan", "receipt"], "word_count": 340},
        {"filename": "tax_form_2025.pdf", "upload_time": "2026-06-19 12:05:00 UTC", "tags": ["pdf", "document", "finance"], "word_count": 2200},
        {"filename": "annual_report.pdf", "upload_time": "2026-06-19 13:40:12 UTC", "tags": ["pdf", "document", "report"], "word_count": 4800},
        {"filename": "handwritten_notes.jpg", "upload_time": "2026-06-19 14:10:05 UTC", "tags": ["image", "scan"], "word_count": 120},
        {"filename": "invoice_1025.pdf", "upload_time": "2026-06-19 14:55:00 UTC", "tags": ["pdf", "document", "invoice"], "word_count": 980},
    ]
    df = pd.DataFrame(mock_records)
    df["upload_time"] = pd.to_datetime(df["upload_time"])
    return df

# Fetch Data from BigQuery
def fetch_data(table_id):
    if bq_client is None:
        return get_mock_data(), True # Return mock data and a flag indicating mock mode
    
    try:
        query = f"SELECT filename, upload_time, tags, word_count FROM `{table_id}` ORDER BY upload_time DESC"
        query_job = bq_client.query(query)
        results = query_job.result()
        
        # Build list of rows
        rows = []
        for row in results:
            rows.append({
                "filename": row.filename,
                "upload_time": row.upload_time,
                "tags": list(row.tags) if row.tags else [],
                "word_count": row.word_count
            })
        
        if not rows:
            return pd.DataFrame(columns=["filename", "upload_time", "tags", "word_count"]), False
            
        df = pd.DataFrame(rows)
        return df, False
    except Exception as e:
        st.sidebar.error(f"Error fetching from BigQuery: {e}")
        return get_mock_data(), True

# App Layout
st.markdown('<h1 class="main-title">📄 Document Pipeline Dashboard</h1>', unsafe_allow_html=True)

# Sidebar Configuration
st.sidebar.header("Data Source Settings")
project_id_default = "mcp-testing-491205"
dataset_default = "document_pipeline"
table_default = "processed_metadata"

table_input = st.sidebar.text_input(
    "BigQuery Table ID", 
    value=f"{project_id_default}.{dataset_default}.{table_default}"
)

refresh_btn = st.sidebar.button("🔄 Refresh Data")

# Fetch Data
df, is_mock = fetch_data(table_input)

# Warning badge if running in mock mode
if is_mock:
    st.warning("⚠️ Running in **Mock Mode** (Local dummy data). Configure GCP Credentials and deploy to view live BigQuery data.")

# Calculate Metrics
total_docs = len(df)
total_words = int(df["word_count"].sum()) if total_docs > 0 else 0
avg_words = int(df["word_count"].mean()) if total_docs > 0 else 0

# Extract all unique tags
all_tags = set()
for tag_list in df["tags"]:
    all_tags.update(tag_list)
sorted_tags = sorted(list(all_tags))

# Display Metrics Cards
m1, m2, m3 = st.columns(3)
with m1:
    st.metric("Total Processed Documents", f"{total_docs} files")
with m2:
    st.metric("Total Word Count (OCR)", f"{total_words:,} words")
with m3:
    st.metric("Average Words per Doc", f"{avg_words:,} words")

st.write("---")

# Filters Section
st.subheader("🔍 Filter & Search")
col_filter, col_search = st.columns([2, 1])

with col_filter:
    selected_tags = st.multiselect("Filter by tags", options=sorted_tags, default=[])

with col_search:
    search_query = st.text_input("Search filename", value="")

# Apply Filters
filtered_df = df.copy()

if selected_tags:
    # Match rows where at least one tag in selected_tags is present in row's tags
    filtered_df = filtered_df[filtered_df["tags"].apply(lambda tags: any(t in tags for t in selected_tags))]

if search_query:
    filtered_df = filtered_df[filtered_df["filename"].str.contains(search_query, case=False)]

# Table Display
st.subheader("Processed Metadata Table")
if not filtered_df.empty:
    # Convert tags array to string for cleaner display in dataframe
    display_df = filtered_df.copy()
    display_df["tags"] = display_df["tags"].apply(lambda tags: ", ".join(tags))
    display_df.rename(columns={
        "filename": "Filename",
        "upload_time": "Upload Time",
        "tags": "Tags",
        "word_count": "Word Count"
    }, inplace=True)
    
    st.dataframe(display_df, use_container_width=True)
else:
    st.info("No records matched your search filters.")

# Visualization Section
if not filtered_df.empty:
    st.write("---")
    st.subheader("📊 Pipeline Insights")
    c1, c2 = st.columns(2)
    
    with c1:
        # Tag distribution
        tag_counts = []
        for tags in filtered_df["tags"]:
            # If tags is string (after display mapping), split it back, otherwise list
            tag_list = tags.split(", ") if isinstance(tags, str) else tags
            tag_counts.extend(tag_list)
        
        if tag_counts:
            tag_df = pd.DataFrame(tag_counts, columns=["Tag"]).value_counts().reset_index(name="Count")
            st.write("#### Document Frequency by Tag")
            st.bar_chart(tag_df.set_index("Tag"))
            
    with c2:
        # Word count per document
        st.write("#### Word Count per Document")
        chart_df = filtered_df[["filename", "word_count"]].rename(columns={"filename": "Document", "word_count": "Words"})
        st.bar_chart(chart_df.set_index("Document"))
