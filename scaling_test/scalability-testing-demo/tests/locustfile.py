from locust import HttpUser, task, between
import random
import json

class ScalabilityTestUser(HttpUser):
    wait_time = between(0.1, 2.0)  # Realistic user timing
    
    def on_start(self):
        """Called when a user starts"""
        self.user_session = f"user_{random.randint(1000, 9999)}"
        
    @task(10)
    def test_light_endpoint(self):
        """Test the light endpoint - high frequency"""
        self.client.get("/light")
        
    @task(5)
    def test_medium_endpoint(self):
        """Test medium complexity endpoint"""
        self.client.get("/medium")
        
    @task(2)
    def test_heavy_endpoint(self):
        """Test heavy processing endpoint"""
        self.client.get("/heavy")
        
    @task(3)
    def test_database_simulation(self):
        """Test database connection behavior"""
        self.client.get("/database-simulation")
        
    @task(1)
    def test_memory_stress(self):
        """Test memory allocation patterns"""
        self.client.get("/memory-stress")
        
    @task(1)
    def test_cascade_behavior(self):
        """Test cascade failure patterns"""
        self.client.get("/cascade-failure")

class SteadyLoadUser(HttpUser):
    """Represents steady background load"""
    wait_time = between(1, 3)
    
    @task
    def background_activity(self):
        self.client.get("/light")

class BurstLoadUser(HttpUser):
    """Represents burst traffic patterns"""
    wait_time = between(0.1, 0.5)
    
    @task
    def burst_requests(self):
        endpoints = ["/light", "/medium", "/database-simulation"]
        endpoint = random.choice(endpoints)
        self.client.get(endpoint)
