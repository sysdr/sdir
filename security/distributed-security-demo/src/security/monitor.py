"""
Security monitoring and threat detection service
"""
import asyncio
import time
import json
import os
from typing import Dict, List, Any
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
import uvicorn
import numpy as np
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
import structlog

logger = structlog.get_logger()

class ThreatDetector:
    def __init__(self):
        self.isolation_forest = IsolationForest(contamination=0.1, random_state=42)
        self.scaler = StandardScaler()
        self.trained = False
        self.request_history = []
        self.threat_rules = self._load_threat_rules()
    
    def _load_threat_rules(self) -> List[Dict]:
        """Load threat detection rules"""
        return [
            {
                "name": "SQL Injection Attempt",
                "pattern": ["select", "union", "drop", "insert", "delete"],
                "severity": "high"
            },
            {
                "name": "XSS Attempt",
                "pattern": ["<script", "javascript:", "onerror="],
                "severity": "high"
            },
            {
                "name": "Directory Traversal",
                "pattern": ["../", "..\\", "%2e%2e"],
                "severity": "medium"
            },
            {
                "name": "Brute Force",
                "condition": "failed_logins > 10",
                "severity": "high"
            }
        ]
    
    def extract_features(self, request_data: Dict) -> List[float]:
        """Extract features from request for ML analysis"""
        features = []
        
        # Request rate features
        features.append(request_data.get("requests_per_minute", 0))
        features.append(request_data.get("unique_endpoints", 0))
        features.append(request_data.get("error_rate", 0))
        
        # Request characteristics
        features.append(len(request_data.get("user_agent", "")))
        features.append(len(request_data.get("payload", "")))
        features.append(request_data.get("response_time", 0))
        
        # Time-based features
        hour = time.localtime().tm_hour
        features.append(hour)
        features.append(1 if 9 <= hour <= 17 else 0)  # Business hours
        
        return features
    
    def detect_rule_based_threats(self, request_data: Dict) -> List[Dict]:
        """Detect threats using rule-based patterns"""
        threats = []
        payload = request_data.get("payload", "").lower()
        user_agent = request_data.get("user_agent", "").lower()
        
        for rule in self.threat_rules:
            if "pattern" in rule:
                for pattern in rule["pattern"]:
                    if pattern in payload or pattern in user_agent:
                        threats.append({
                            "type": "rule_based",
                            "rule_name": rule["name"],
                            "severity": rule["severity"],
                            "pattern_matched": pattern,
                            "timestamp": time.time()
                        })
        
        return threats
    
    def detect_ml_anomalies(self, request_data: Dict) -> List[Dict]:
        """Detect anomalies using machine learning"""
        threats = []
        
        features = self.extract_features(request_data)
        self.request_history.append(features)
        
        # Keep only recent history (last 1000 requests)
        if len(self.request_history) > 1000:
            self.request_history = self.request_history[-1000:]
        
        # Train model if we have enough data
        if len(self.request_history) >= 100 and not self.trained:
            X = np.array(self.request_history)
            X_scaled = self.scaler.fit_transform(X)
            self.isolation_forest.fit(X_scaled)
            self.trained = True
            logger.info("ML threat detection model trained")
        
        # Detect anomalies
        if self.trained:
            X = np.array([features])
            X_scaled = self.scaler.transform(X)
            anomaly_score = self.isolation_forest.decision_function(X_scaled)[0]
            is_anomaly = self.isolation_forest.predict(X_scaled)[0] == -1
            
            if is_anomaly:
                threats.append({
                    "type": "ml_anomaly",
                    "anomaly_score": float(anomaly_score),
                    "severity": "medium" if anomaly_score > -0.5 else "high",
                    "timestamp": time.time()
                })
        
        return threats
    
    def analyze_request(self, request_data: Dict) -> Dict:
        """Comprehensive threat analysis of a request"""
        rule_threats = self.detect_rule_based_threats(request_data)
        ml_threats = self.detect_ml_anomalies(request_data)
        
        all_threats = rule_threats + ml_threats
        
        # Determine overall risk level
        if any(t["severity"] == "high" for t in all_threats):
            risk_level = "high"
        elif any(t["severity"] == "medium" for t in all_threats):
            risk_level = "medium"
        else:
            risk_level = "low"
        
        return {
            "risk_level": risk_level,
            "threats_detected": len(all_threats),
            "threats": all_threats,
            "timestamp": time.time()
        }

class SecurityMonitor:
    def __init__(self):
        self.app = FastAPI(title="Security Monitor")
        self.threat_detector = ThreatDetector()
        self.active_connections: List[WebSocket] = []
        self.security_events = []
        self.blocked_ips = set()
        
        # Setup routes
        self.setup_routes()
        
        # Setup startup event to start background monitoring
        @self.app.on_event("startup")
        async def startup_event():
            asyncio.create_task(self.monitor_threats())
    
    async def monitor_threats(self):
        """Background task to monitor for threats"""
        while True:
            try:
                # Simulate incoming security events
                await self.generate_sample_events()
                await asyncio.sleep(5)  # Check every 5 seconds
            except Exception as e:
                logger.error("Error in threat monitoring", error=str(e))
                await asyncio.sleep(10)
    
    async def generate_sample_events(self):
        """Generate sample security events for demonstration"""
        import random
        
        # Simulate various request patterns
        sample_requests = [
            {
                "client_ip": f"192.168.1.{random.randint(1, 100)}",
                "requests_per_minute": random.randint(1, 200),
                "unique_endpoints": random.randint(1, 50),
                "error_rate": random.random() * 0.5,
                "user_agent": "Mozilla/5.0 (Normal Browser)",
                "payload": "normal request data",
                "response_time": random.random() * 2
            },
            # Suspicious patterns
            {
                "client_ip": "10.0.0.666",
                "requests_per_minute": 150,
                "unique_endpoints": 45,
                "error_rate": 0.8,
                "user_agent": "python-requests/2.25.1",
                "payload": "select * from users where id=1 union select password from admin",
                "response_time": 0.1
            }
        ]
        
        for request_data in sample_requests:
            analysis = self.threat_detector.analyze_request(request_data)
            
            if analysis["threats_detected"] > 0:
                event = {
                    "client_ip": request_data["client_ip"],
                    "analysis": analysis,
                    "timestamp": time.time()
                }
                
                self.security_events.append(event)
                
                # Auto-block high-risk IPs
                if analysis["risk_level"] == "high":
                    self.blocked_ips.add(request_data["client_ip"])
                    logger.warning("IP blocked due to high threat level", ip=request_data["client_ip"])
                
                # Broadcast to connected clients
                await self.broadcast_security_event(event)
        
        # Keep only recent events
        hour_ago = time.time() - 3600
        self.security_events = [e for e in self.security_events if e["timestamp"] > hour_ago]
    
    async def broadcast_security_event(self, event: Dict):
        """Broadcast security event to all connected WebSocket clients"""
        message = json.dumps(event)
        disconnected = []
        
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except:
                disconnected.append(connection)
        
        # Remove disconnected clients
        for connection in disconnected:
            self.active_connections.remove(connection)
    
    def setup_routes(self):
        """Setup API routes"""
        
        @self.app.get("/")
        async def dashboard():
            with open("src/web/templates/security_dashboard.html", "r") as f:
                html_content = f.read()
            return HTMLResponse(content=html_content)
        
        @self.app.get("/api/security/status")
        async def security_status():
            return {
                "threat_detector_trained": self.threat_detector.trained,
                "active_threats": len([e for e in self.security_events if e["analysis"]["risk_level"] == "high"]),
                "blocked_ips": len(self.blocked_ips),
                "total_events": len(self.security_events),
                "ml_model_samples": len(self.threat_detector.request_history)
            }
        
        @self.app.get("/api/security/events")
        async def get_security_events():
            return {
                "events": self.security_events[-50:],  # Last 50 events
                "blocked_ips": list(self.blocked_ips)
            }
        
        @self.app.post("/api/security/analyze")
        async def analyze_request(request_data: dict):
            analysis = self.threat_detector.analyze_request(request_data)
            return analysis
        
        @self.app.websocket("/ws/security")
        async def websocket_endpoint(websocket: WebSocket):
            await websocket.accept()
            self.active_connections.append(websocket)
            
            try:
                while True:
                    # Keep connection alive
                    await websocket.receive_text()
            except WebSocketDisconnect:
                self.active_connections.remove(websocket)
    
    def run(self):
        """Run the security monitor"""
        logger.info("Starting security monitor")
        
        uvicorn.run(
            self.app,
            host="0.0.0.0",
            port=8080
        )

def main():
    monitor = SecurityMonitor()
    monitor.run()

if __name__ == "__main__":
    main()
