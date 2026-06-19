import os
import logging
import random
import datetime
from typing import Dict, Any, List
from fastapi import FastAPI, Request, HTTPException
from google.cloud import storage
from google.cloud import bigquery
from google.auth.exceptions import DefaultCredentialsError

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("processor")

app = FastAPI(title="GCS Eventarc Document Processor")

# Initialize GCP clients
def get_gcs_client():
    # If K_SERVICE is not set and no credentials variable exists, default to mock immediately to avoid metadata timeout
    if not os.environ.get("K_SERVICE") and not os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"):
        logger.info("Running locally without GCP credentials. GCS client will operate in mock mode.")
        return None
    try:
        return storage.Client()
    except Exception as e:
        logger.warning(f"GCS client failed to initialize: {e}. Running in local/mock mode for GCS.")
        return None

def get_bigquery_client():
    if not os.environ.get("K_SERVICE") and not os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"):
        logger.info("Running locally without GCP credentials. BigQuery client will operate in mock mode.")
        return None
    try:
        return bigquery.Client()
    except Exception as e:
        logger.warning(f"BigQuery client failed to initialize: {e}. Running in local/mock mode for BigQuery.")
        return None

gcs_client = get_gcs_client()
bq_client = get_bigquery_client()

# Fetch target BigQuery config from environment variables
DATASET_ID = os.environ.get("BIGQUERY_DATASET", "document_pipeline")
TABLE_ID = os.environ.get("BIGQUERY_TABLE", "processed_metadata")

def simulate_ocr(filename: str) -> Dict[str, Any]:
    """
    Simulates OCR process on the file based on its name and extension.
    Returns tags and word count.
    """
    name_lower = filename.lower()
    base, ext = os.path.splitext(name_lower)
    
    tags = []
    
    # Generate tags based on extension
    if ext == '.pdf':
        tags.extend(["pdf", "document"])
    elif ext in ['.png', '.jpg', '.jpeg', '.tiff']:
        tags.extend(["image", "scan"])
    elif ext in ['.txt', '.md', '.csv']:
        tags.extend(["text", "raw"])
    else:
        tags.append("unknown-format")
        
    # Generate tags based on filename keywords
    if "invoice" in name_lower:
        tags.append("invoice")
    if "receipt" in name_lower:
        tags.append("receipt")
    if "report" in name_lower:
        tags.append("report")
    if "tax" in name_lower:
        tags.append("finance")
        
    # Remove duplicates
    tags = list(set(tags))
    if not tags:
        tags = ["upload"]

    # Use hash of filename to generate a stable mock word count
    # or simple deterministic random
    random.seed(filename)
    word_count = random.randint(50, 2500)
    
    return {
        "tags": tags,
        "word_count": word_count
    }

@app.post("/")
async def handle_event(request: Request):
    """
    Handles incoming Eventarc CloudEvents.
    Can handle both binary mode (headers) and structured mode (body).
    """
    headers = request.headers
    body = await request.json()
    
    logger.info(f"Received request headers: {dict(headers)}")
    logger.info(f"Received request body: {body}")
    
    bucket = None
    name = None
    
    # 1. Check if Eventarc/CloudEvent headers exist (Binary Content Mode)
    # GCS notifications will set ce-subject (e.g. objects/filename) and headers like ce-bucket
    if "ce-subject" in headers:
        subject = headers["ce-subject"]
        # ce-subject is usually formatted as 'objects/path/to/file.ext'
        if subject.startswith("objects/"):
            name = subject[len("objects/"):]
            
    # GCS Eventarc also specifies the bucket in headers (usually ce-bucket or in payload)
    if "ce-bucket" in headers:
        bucket = headers["ce-bucket"]
        
    # 2. Check Structured Content Mode or direct JSON body payload
    if not bucket or not name:
        # Eventarc payloads for storage events wrap the resource attributes in the "data" field
        data = body.get("data", body) if isinstance(body, dict) else {}
        if isinstance(data, dict):
            bucket = data.get("bucket", bucket)
            name = data.get("name", name)
            
    if not bucket or not name:
        logger.error("Could not extract GCS bucket or object name from request.")
        raise HTTPException(status_code=400, detail="Missing GCS bucket or object name in CloudEvent.")
        
    logger.info(f"Processing GCS file: gs://{bucket}/{name}")
    
    # Perform simulated OCR
    ocr_result = simulate_ocr(name)
    tags = ocr_result["tags"]
    word_count = ocr_result["word_count"]
    
    upload_time = datetime.datetime.utcnow().isoformat() + "Z"
    
    # Check if we can get file metadata from GCS (such as actual size, content type)
    file_size_bytes = None
    content_type = "unknown"
    if gcs_client:
        try:
            bucket_obj = gcs_client.bucket(bucket)
            blob = bucket_obj.get_blob(name)
            if blob:
                file_size_bytes = blob.size
                content_type = blob.content_type
                logger.info(f"Retrieved actual file size: {file_size_bytes} bytes, content_type: {content_type}")
        except Exception as e:
            logger.warning(f"Could not retrieve file metadata from GCS: {e}")

    # Prepare BigQuery Row
    row = {
        "filename": name,
        "upload_time": upload_time,
        "tags": tags,
        "word_count": word_count
    }
    
    # Write to BigQuery
    if bq_client:
        try:
            table_ref = bq_client.dataset(DATASET_ID).table(TABLE_ID)
            errors = bq_client.insert_rows_json(table_ref, [row])
            if errors:
                logger.error(f"BigQuery stream errors: {errors}")
                raise HTTPException(status_code=500, detail=f"BigQuery streaming failed: {errors}")
            else:
                logger.info(f"Successfully streamed row to BigQuery: {row}")
        except Exception as e:
            logger.error(f"Failed to write to BigQuery: {e}")
            raise HTTPException(status_code=500, detail=f"Database connection error: {e}")
    else:
        logger.info(f"[MOCK MODE] BigQuery insert would be: {row}")
        
    return {
        "status": "success",
        "processed_file": f"gs://{bucket}/{name}",
        "metadata": row
    }

@app.get("/health")
def health_check():
    return {"status": "healthy", "gcs_connected": gcs_client is not None, "bq_connected": bq_client is not None}

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
