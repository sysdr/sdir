from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
import httpx
import asyncio

app = FastAPI()
templates = Jinja2Templates(directory="templates")

@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})

@app.post("/create-order")
async def create_order(request: Request):
    data = await request.json()
    
    # Use localhost instead of service names from web UI
    timeout = httpx.Timeout(10.0, read=60.0)
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            response = await client.post("http://order-service:8000/create-order", json=data)
            if response.status_code == 200:
                return response.json()
            else:
                return {"error": f"HTTP {response.status_code}: {response.text}"}
        except Exception as e:
            return {"error": str(e)}

@app.get("/saga-status/{transaction_id}")
async def saga_status(transaction_id: str):
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(f"http://order-service:8000/saga/{transaction_id}")
            return response.json()
        except Exception as e:
            return {"error": str(e)}

@app.get("/inventory")
async def inventory():
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get("http://inventory-service:8002/inventory")
            return response.json()
        except Exception as e:
            return {"error": str(e)}
