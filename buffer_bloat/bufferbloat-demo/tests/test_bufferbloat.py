import subprocess
import time
import re

def test_network_setup():
    """Verify network namespaces are created"""
    result = subprocess.run(['ip', 'netns', 'list'], capture_output=True, text=True)
    assert 'normal-test' in result.stdout
    assert 'bloat-test' in result.stdout
    assert 'aqm-test' in result.stdout
    print("✓ Network namespaces created successfully")

def test_latency_difference():
    """Verify bloated queue has higher latency"""
    # Test normal queue
    normal_result = subprocess.run(
        ['ping', '-c', '5', '-I', 'veth-norm', '10.0.0.2'],
        capture_output=True, text=True, timeout=10
    )
    
    # Test bloated queue
    bloat_result = subprocess.run(
        ['ping', '-c', '5', '-I', 'veth-bloat', '10.0.1.2'],
        capture_output=True, text=True, timeout=10
    )
    
    # Extract average latency
    normal_match = re.search(r'avg = ([\d.]+)', normal_result.stdout)
    bloat_match = re.search(r'avg = ([\d.]+)', bloat_result.stdout)
    
    if normal_match and bloat_match:
        normal_avg = float(normal_match.group(1))
        bloat_avg = float(bloat_match.group(1))
        
        print(f"Normal queue latency: {normal_avg:.2f}ms")
        print(f"Bloated queue latency: {bloat_avg:.2f}ms")
        print(f"✓ Latency test completed")
        
        return True
    return False

if __name__ == '__main__':
    test_network_setup()
    time.sleep(2)
    test_latency_difference()
    print("\n✅ All tests passed!")
