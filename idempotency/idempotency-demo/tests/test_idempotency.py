import pytest
import json
import uuid
from app import app, db, Payment, IdempotencyRecord

@pytest.fixture
def client():
    app.config['TESTING'] = True
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
    
    with app.test_client() as client:
        with app.app_context():
            db.create_all()
            yield client

def test_idempotent_payment_processing(client):
    """Test that identical payments return the same result"""
    payment_data = {
        'amount': 100.00,
        'currency': 'USD',
        'customer_id': 'test_customer',
        'idempotency_key': 'test_key_' + str(uuid.uuid4())
    }
    
    # First request
    response1 = client.post('/api/payment', 
                           data=json.dumps(payment_data),
                           content_type='application/json')
    
    # Second identical request
    response2 = client.post('/api/payment',
                           data=json.dumps(payment_data),
                           content_type='application/json')
    
    assert response1.status_code == 200
    assert response2.status_code == 200
    
    data1 = json.loads(response1.data)
    data2 = json.loads(response2.data)
    
    # Should have same payment ID
    assert data1['payment_id'] == data2['payment_id']
    assert data1['status'] == data2['status']

def test_different_idempotency_keys_create_different_payments(client):
    """Test that different idempotency keys create separate payments"""
    payment_data1 = {
        'amount': 100.00,
        'currency': 'USD',
        'customer_id': 'test_customer',
        'idempotency_key': 'key1_' + str(uuid.uuid4())
    }
    
    payment_data2 = {
        'amount': 100.00,
        'currency': 'USD',
        'customer_id': 'test_customer',
        'idempotency_key': 'key2_' + str(uuid.uuid4())
    }
    
    response1 = client.post('/api/payment',
                           data=json.dumps(payment_data1),
                           content_type='application/json')
    
    response2 = client.post('/api/payment',
                           data=json.dumps(payment_data2),
                           content_type='application/json')
    
    assert response1.status_code == 200
    assert response2.status_code == 200
    
    data1 = json.loads(response1.data)
    data2 = json.loads(response2.data)
    
    # Should have different payment IDs
    assert data1['payment_id'] != data2['payment_id']

def test_retry_simulation(client):
    """Test retry simulation returns consistent results"""
    retry_data = {
        'amount': 50.00,
        'currency': 'USD',
        'customer_id': 'retry_customer',
        'retry_count': 3
    }
    
    response = client.post('/api/simulate-retry',
                          data=json.dumps(retry_data),
                          content_type='application/json')
    
    assert response.status_code == 200
    data = json.loads(response.data)
    
    assert data['all_identical'] == True
    assert len(data['results']) == 3
    
    # All payment IDs should be the same
    payment_ids = [result['payment_id'] for result in data['results']]
    assert len(set(payment_ids)) == 1

if __name__ == '__main__':
    pytest.main([__file__])
