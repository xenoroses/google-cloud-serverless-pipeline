import urllib.request
import json
import time

def send_mock_event(filename, bucket="mock-upload-bucket"):
    url = "http://localhost:8080/"
    
    # Eventarc delivers storage objects using CloudEvents.
    # We can simulate Binary Content Mode by setting ce- headers,
    # or Structured Content Mode by providing a wrapping data object.
    # Let's test using the Structured JSON format:
    payload = {
        "specversion": "1.0",
        "id": "1234-5678-90ab",
        "source": f"//storage.googleapis.com/projects/_/buckets/{bucket}",
        "type": "google.cloud.storage.object.v1.finalized",
        "subject": f"objects/{filename}",
        "time": "2026-06-19T12:00:00Z",
        "data": {
            "bucket": bucket,
            "name": filename,
            "metageneration": "1",
            "timeCreated": "2026-06-19T12:00:00Z",
            "updated": "2026-06-19T12:00:00Z"
        }
    }
    
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    
    print(f"\n---> Sending mock event for: {filename}")
    try:
        with urllib.request.urlopen(req) as response:
            status = response.getcode()
            response_body = response.read().decode('utf-8')
            print(f"Response Status: {status}")
            print("Response Payload:")
            print(json.dumps(json.loads(response_body), indent=2))
    except urllib.error.HTTPError as e:
        print(f"HTTP Error: {e.code} - {e.reason}")
        print(e.read().decode('utf-8'))
    except Exception as e:
        print(f"Error connecting to local server: {e}")
        print("Make sure your FastAPI server is running locally (e.g. `uvicorn main:app --port 8080` in src/processor)")

if __name__ == "__main__":
    print("Testing local Cloud Run processor...")
    print("Files simulated: invoice_998.pdf, store_receipt.png, document_quarterly_report.txt, readme.md")
    
    send_mock_event("invoice_998.pdf")
    time.sleep(1)
    send_mock_event("store_receipt.png")
    time.sleep(1)
    send_mock_event("document_quarterly_report.txt")
    time.sleep(1)
    send_mock_event("unknown_file.bin")
