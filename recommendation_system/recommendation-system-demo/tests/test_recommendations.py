import requests
import time
import json

API_BASE = "http://localhost:8000"

def test_api_health():
    response = requests.get(f"{API_BASE}/")
    assert response.status_code == 200
    print("✅ API health check passed")

def test_users_endpoint():
    response = requests.get(f"{API_BASE}/users")
    assert response.status_code == 200
    users = response.json()
    assert len(users) > 0
    print(f"✅ Users endpoint returned {len(users)} users")

def test_recommendations():
    # Get users first
    users_response = requests.get(f"{API_BASE}/users")
    users = users_response.json()
    user_id = users[0]["id"]
    
    # Test each algorithm
    algorithms = ["collaborative", "content_based", "hybrid"]
    for algorithm in algorithms:
        response = requests.get(f"{API_BASE}/recommendations/{user_id}?algorithm={algorithm}")
        assert response.status_code == 200
        recommendations = response.json()
        print(f"✅ {algorithm} algorithm returned {len(recommendations)} recommendations")

def test_interactions():
    users_response = requests.get(f"{API_BASE}/users")
    users = users_response.json()
    user_id = users[0]["id"]
    
    # Create interaction
    response = requests.post(f"{API_BASE}/interactions", params={
        "user_id": user_id,
        "item_id": 1,
        "interaction_type": "view",
        "rating": 4.5
    })
    assert response.status_code == 200
    print("✅ Interaction creation test passed")

def test_performance_metrics():
    response = requests.get(f"{API_BASE}/analytics/performance")
    assert response.status_code == 200
    metrics = response.json()
    assert "avg_response_time_ms" in metrics
    print("✅ Performance metrics test passed")

if __name__ == "__main__":
    print("🧪 Testing Recommendation System API...")
    
    # Wait for services to be ready
    max_retries = 30
    for i in range(max_retries):
        try:
            test_api_health()
            break
        except:
            if i == max_retries - 1:
                print("❌ API not ready after 30 retries")
                exit(1)
            print(f"Waiting for API... ({i+1}/{max_retries})")
            time.sleep(2)
    
    test_users_endpoint()
    test_recommendations()
    test_interactions()
    test_performance_metrics()
    
    print("\n🎉 All tests passed! Recommendation system is working correctly.")
