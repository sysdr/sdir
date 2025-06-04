#!/usr/bin/env python3
import requests
import time
import json
import random

def wait_for_nodes():
    """Wait for all nodes to be ready"""
    nodes = [8080, 8081, 8082, 8083, 8084]
    print("Waiting for all nodes to be ready...")
    
    while True:
        ready_count = 0
        for port in nodes:
            try:
                response = requests.get(f"http://localhost:{port}/status", timeout=2)
                if response.status_code == 200:
                    ready_count += 1
            except:
                pass
        
        if ready_count == len(nodes):
            print(f"✅ All {len(nodes)} nodes are ready!")
            break
        else:
            print(f"⏳ {ready_count}/{len(nodes)} nodes ready, waiting...")
            time.sleep(2)

def test_basic_operations():
    """Test basic read/write operations"""
    print("\n" + "="*60)
    print("🧪 TESTING: Basic Read/Write Operations")
    print("="*60)
    
    coordinator = 8080
    
    # Test write
    print("1. Writing test data...")
    data = {
        "user:1": "Alice",
        "user:2": "Bob", 
        "product:100": "Gaming Laptop",
        "session:abc123": "active"
    }
    
    for key, value in data.items():
        response = requests.post(
            f"http://localhost:{coordinator}/coordinate_write",
            json={"key": key, "value": value, "w": 2}
        )
        result = response.json()
        status = "✅" if result["success"] else "❌"
        print(f"   {status} Write {key}: {result['success']}")
    
    time.sleep(1)
    
    # Test reads
    print("\n2. Reading test data...")
    for key in data.keys():
        response = requests.get(f"http://localhost:{coordinator}/coordinate_read?key={key}&r=2")
        result = response.json()
        status = "✅" if result["success"] else "❌"
        value = result.get("value", "NOT_FOUND")
        print(f"   {status} Read {key}: {value}")

def test_consistency_levels():
    """Test different consistency levels"""
    print("\n" + "="*60)
    print("🧪 TESTING: Different Consistency Levels")
    print("="*60)
    
    coordinator = 8080
    test_key = "consistency_test"
    
    consistency_levels = [
        (1, 1, "Eventual Consistency"),
        (2, 2, "Default Quorum"),
        (3, 3, "Strong Consistency"),
        (5, 5, "Strongest Consistency")
    ]
    
    for r, w, description in consistency_levels:
        print(f"\n📊 Testing {description} (R={r}, W={w})")
        
        # Write
        write_response = requests.post(
            f"http://localhost:{coordinator}/coordinate_write",
            json={"key": test_key, "value": f"value_r{r}_w{w}", "w": w}
        )
        write_result = write_response.json()
        
        # Read
        read_response = requests.get(
            f"http://localhost:{coordinator}/coordinate_read?key={test_key}&r={r}"
        )
        read_result = read_response.json()
        
        write_status = "✅" if write_result["success"] else "❌"
        read_status = "✅" if read_result["success"] else "❌"
        
        print(f"   {write_status} Write: {write_result['success']}")
        print(f"   {read_status} Read: {read_result['success']}")
        
        time.sleep(0.5)

def test_failure_scenarios():
    """Test various failure scenarios"""
    print("\n" + "="*60)
    print("🧪 TESTING: Failure Scenarios")
    print("="*60)
    
    nodes = [8080, 8081, 8082, 8083, 8084]
    coordinator = 8080
    
    # 1. Single node failure
    print("\n1. Testing single node failure...")
    print("   Failing node 8081...")
    requests.get("http://localhost:8081/fail")
    
    # Test operations with one node down
    write_response = requests.post(
        f"http://localhost:{coordinator}/coordinate_write",
        json={"key": "failure_test_1", "value": "single_failure", "w": 2}
    )
    write_result = write_response.json()
    
    read_response = requests.get(
        f"http://localhost:{coordinator}/coordinate_read?key=failure_test_1&r=2"
    )
    read_result = read_response.json()
    
    print(f"   ✅ Write with 1 node down: {write_result['success']}")
    print(f"   ✅ Read with 1 node down: {read_result['success']}")
    
    # 2. Multiple node failures
    print("\n2. Testing multiple node failures...")
    print("   Failing node 8082...")
    requests.get("http://localhost:8082/fail")
    
    write_response = requests.post(
        f"http://localhost:{coordinator}/coordinate_write",
        json={"key": "failure_test_2", "value": "dual_failure", "w": 2}
    )
    write_result = write_response.json()
    
    print(f"   ✅ Write with 2 nodes down: {write_result['success']}")
    
    # 3. Quorum loss scenario
    print("\n3. Testing quorum loss scenario...")
    print("   Failing node 8083...")
    requests.get("http://localhost:8083/fail")
    
    write_response = requests.post(
        f"http://localhost:{coordinator}/coordinate_write",
        json={"key": "failure_test_3", "value": "quorum_loss", "w": 3}
    )
    write_result = write_response.json()
    
    print(f"   ❌ Write with quorum loss (W=3, only 2 healthy): {write_result['success']}")
    
    # Recovery
    print("\n4. Testing node recovery...")
    for port in [8081, 8082, 8083]:
        print(f"   Recovering node {port}...")
        requests.get(f"http://localhost:{port}/recover")
        time.sleep(0.5)
    
    write_response = requests.post(
        f"http://localhost:{coordinator}/coordinate_write",
        json={"key": "recovery_test", "value": "all_recovered", "w": 3}
    )
    write_result = write_response.json()
    
    print(f"   ✅ Write after recovery: {write_result['success']}")

def test_read_repair():
    """Test read repair mechanism"""
    print("\n" + "="*60)
    print("🧪 TESTING: Read Repair Mechanism")
    print("="*60)
    
    # Create inconsistency by writing to subset of replicas
    print("1. Creating artificial inconsistency...")
    
    # Write directly to individual nodes with different values
    key = "repair_test"
    
    # Write old value to nodes 8080, 8081
    old_data = {
        "key": key,
        "value": "old_value",
        "timestamp": time.time() - 10,  # Older timestamp
        "version": "old_version"
    }
    
    for port in [8080, 8081]:
        requests.post(f"http://localhost:{port}/write", json=old_data)
    
    time.sleep(0.1)
    
    # Write new value to nodes 8082, 8083, 8084
    new_data = {
        "key": key,
        "value": "new_value", 
        "timestamp": time.time(),  # Newer timestamp
        "version": "new_version"
    }
    
    for port in [8082, 8083, 8084]:
        requests.post(f"http://localhost:{port}/write", json=new_data)
    
    print("   ✅ Artificial inconsistency created")
    
    # Perform read that should trigger repair
    print("\n2. Performing read to trigger repair...")
    read_response = requests.get("http://localhost:8080/coordinate_read?key=repair_test&r=3")
    read_result = read_response.json()
    
    print(f"   ✅ Read result: {read_result.get('value', 'NOT_FOUND')}")
    print(f"   ⚠️ Inconsistency detected: {read_result.get('inconsistency_detected', False)}")
    
    # Wait for repair to complete
    time.sleep(2)
    
    # Verify all nodes have consistent data
    print("\n3. Verifying repair completion...")
    values = []
    for port in [8080, 8081, 8082, 8083, 8084]:
        try:
            response = requests.get(f"http://localhost:{port}/read?key={key}")
            data = response.json()
            if data.get("found"):
                values.append(data["value"])
            else:
                values.append("NOT_FOUND")
        except:
            values.append("ERROR")
    
    unique_values = set(values)
    print(f"   📊 Values across nodes: {values}")
    print(f"   ✅ Consistency achieved: {len(unique_values) == 1}")

def generate_load_test():
    """Generate realistic load to demonstrate system behavior"""
    print("\n" + "="*60)
    print("🧪 TESTING: Load Generation")
    print("="*60)
    
    coordinator = 8080
    operations = 20
    
    print(f"Generating {operations} random operations...")
    
    keys = [f"user:{i}" for i in range(1, 11)] + [f"product:{i}" for i in range(100, 111)]
    values = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Gaming Laptop", "Smartphone", "Tablet", "Monitor", "Keyboard"]
    
    success_count = 0
    
    for i in range(operations):
        op_type = random.choice(["read", "write"])
        key = random.choice(keys)
        
        if op_type == "write":
            value = random.choice(values)
            try:
                response = requests.post(
                    f"http://localhost:{coordinator}/coordinate_write",
                    json={"key": key, "value": value, "w": 2},
                    timeout=5
                )
                result = response.json()
                if result["success"]:
                    success_count += 1
                    print(f"   ✅ Write {i+1}: {key} = {value}")
                else:
                    print(f"   ❌ Write {i+1}: {key} FAILED")
            except Exception as e:
                print(f"   ❌ Write {i+1}: {key} ERROR - {e}")
        else:
            try:
                response = requests.get(
                    f"http://localhost:{coordinator}/coordinate_read?key={key}&r=2",
                    timeout=5
                )
                result = response.json()
                if result["success"]:
                    success_count += 1
                    print(f"   ✅ Read {i+1}: {key} = {result['value']}")
                else:
                    print(f"   ❌ Read {i+1}: {key} NOT_FOUND")
            except Exception as e:
                print(f"   ❌ Read {i+1}: {key} ERROR - {e}")
        
        time.sleep(0.1)  # Small delay between operations
    
    print(f"\n📊 Load test completed: {success_count}/{operations} operations successful")

def main():
    print("🚀 Starting Quorum System Test Suite")
    print("=" * 60)
    
    # Wait for cluster to be ready
    wait_for_nodes()
    
    # Run test scenarios
    test_basic_operations()
    test_consistency_levels()
    test_failure_scenarios()
    test_read_repair()
    generate_load_test()
    
    print("\n" + "="*60)
    print("🎉 All tests completed!")
    print("="*60)
    print("💡 Open http://localhost:8090 to view the web interface")
    print("📋 Check the logs/ directory for detailed node logs")

if __name__ == "__main__":
    main()
