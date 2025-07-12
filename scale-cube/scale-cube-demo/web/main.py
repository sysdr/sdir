from fastapi import FastAPI, Request
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
import httpx
import os
import uvicorn

GATEWAY_URL = os.getenv("GATEWAY_URL", "http://localhost")

app = FastAPI(title="Scale Cube Demo UI")

templates = Jinja2Templates(directory="web/templates")
app.mount("/static", StaticFiles(directory="web/static"), name="static")

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard showing scale cube demonstration"""
    
    # Fetch scaling information
    try:
        async with httpx.AsyncClient() as client:
            scaling_info = await client.get(f"{GATEWAY_URL}/api/scaling-info")
            health_info = await client.get(f"{GATEWAY_URL}/health")
            scaling_data = scaling_info.json()
            health_data = health_info.json()
    except:
        scaling_data = {"error": "Could not connect to gateway"}
        health_data = {"error": "Could not connect to gateway"}
    
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "scaling_info": scaling_data,
        "health_info": health_data
    })

@app.get("/test-scaling", response_class=HTMLResponse)
async def test_scaling(request: Request):
    """Test page to demonstrate scaling in action"""
    return templates.TemplateResponse("test_scaling.html", {
        "request": request
    })

# Proxy endpoints to forward API requests to the gateway
@app.get("/api/scaling-info")
async def proxy_scaling_info():
    """Proxy scaling info requests to gateway"""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{GATEWAY_URL}/api/scaling-info")
        return response.json()

@app.api_route("/api/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def proxy_api(path: str, request: Request):
    """Proxy all other API requests to gateway"""
    body = await request.body()
    
    async with httpx.AsyncClient() as client:
        response = await client.request(
            method=request.method,
            url=f"{GATEWAY_URL}/api/{path}",
            content=body,
            headers=dict(request.headers)
        )
        return response.json()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=3000)
