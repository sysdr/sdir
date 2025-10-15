import requests
import time
import json

# API endpoints
ORDER_API = "http://localhost:8001"
INVENTORY_API = "http://localhost:8002"
SHIPPING_API = "http://localhost:8003"

def test_order_creation():
    """Test order creation and domain logic"""
    print("🧪 Testing Order Creation...")
    
    # Create order
    response = requests.post(f"{ORDER_API}/orders", json={
        "customer_id": "TEST_CUSTOMER"
    })
    assert response.status_code == 200
    order_id = response.json()["order_id"]
    print(f"✅ Order created: {order_id}")
    
    # Add item
    response = requests.post(f"{ORDER_API}/orders/{order_id}/items", json={
        "product_id": "LAPTOP001",
        "product_name": "Gaming Laptop",
        "quantity": 1,
        "price": 299.99
    })
    assert response.status_code == 200
    print("✅ Item added to order")
    
    # Set address
    response = requests.put(f"{ORDER_API}/orders/{order_id}/address", json={
        "street": "123 Test St",
        "city": "Test City", 
        "state": "TS",
        "zip_code": "12345"
    })
    assert response.status_code == 200
    print("✅ Address set")
    
    return order_id

def test_event_driven_flow():
    """Test complete DDD event flow"""
    print("🧪 Testing Event-Driven Flow...")
    
    # Get initial inventory
    response = requests.get(f"{INVENTORY_API}/products/LAPTOP001")
    initial_available = response.json()["available_quantity"]
    print(f"📦 Initial available quantity: {initial_available}")
    
    # Create and confirm order
    order_id = test_order_creation()
    
    # Confirm order (triggers events)
    response = requests.post(f"{ORDER_API}/orders/{order_id}/confirm")
    assert response.status_code == 200
    print("✅ Order confirmed - events should be flowing...")
    
    # Wait for event processing
    time.sleep(3)
    
    # Check inventory was reserved
    response = requests.get(f"{INVENTORY_API}/products/LAPTOP001")
    new_available = response.json()["available_quantity"]
    assert new_available == initial_available - 1
    print(f"✅ Inventory updated: {new_available} available")
    
    # Check shipment was created
    response = requests.get(f"{SHIPPING_API}/shipments")
    shipments = response.json()
    order_shipments = [s for s in shipments if s["order_id"] == order_id]
    assert len(order_shipments) > 0
    print("✅ Shipment created")
    
    print("🎉 Complete DDD flow working!")

def test_domain_invariants():
    """Test domain model business rules"""
    print("🧪 Testing Domain Invariants...")
    
    # Create order
    response = requests.post(f"{ORDER_API}/orders", json={
        "customer_id": "TEST_CUSTOMER"
    })
    order_id = response.json()["order_id"]
    
    # Try to confirm empty order (should fail)
    response = requests.post(f"{ORDER_API}/orders/{order_id}/confirm")
    assert response.status_code == 400
    print("✅ Empty order confirmation blocked")
    
    # Add item
    requests.post(f"{ORDER_API}/orders/{order_id}/items", json={
        "product_id": "LAPTOP001",
        "product_name": "Gaming Laptop",
        "quantity": 1,
        "price": 299.99
    })
    
    # Try to confirm without address (should fail)
    response = requests.post(f"{ORDER_API}/orders/{order_id}/confirm")
    assert response.status_code == 400
    print("✅ Order without address blocked")
    
    print("✅ Domain invariants enforced!")

def run_all_tests():
    """Run complete test suite"""
    print("🚀 Starting DDD System Tests...\n")
    
    try:
        # Wait for services to be ready
        print("⏳ Waiting for services to start...")
        time.sleep(10)
        
        # Check service health
        for service, url in [("Order", ORDER_API), ("Inventory", INVENTORY_API), ("Shipping", SHIPPING_API)]:
            response = requests.get(f"{url}/")
            assert response.status_code == 200
            print(f"✅ {service} service healthy")
        
        print("\n" + "="*50)
        test_order_creation()
        print("\n" + "="*50)
        test_event_driven_flow()
        print("\n" + "="*50)
        test_domain_invariants()
        print("\n" + "="*50)
        
        print("🎉 All tests passed! DDD system is working correctly.")
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        raise

if __name__ == "__main__":
    run_all_tests()

