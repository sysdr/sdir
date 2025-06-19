"""
Test suite for Event Sourcing Demo
Validates core event sourcing patterns and behaviors
"""

import pytest
import sqlite3
import tempfile
import os
from datetime import datetime, timedelta
from src.main import EventStore, AccountAggregate, Event, EventType

class TestEventSourcing:
    """Test event sourcing implementation"""
    
    @pytest.fixture
    def event_store(self):
        """Create a temporary event store for testing"""
        db_path = tempfile.mktemp(suffix='.db')
        store = EventStore(db_path)
        yield store
        # Cleanup
        if os.path.exists(db_path):
            os.unlink(db_path)
    
    @pytest.fixture
    def account_aggregate(self, event_store):
        """Create account aggregate with test event store"""
        return AccountAggregate(event_store)
    
    def test_account_creation(self, account_aggregate):
        """Test basic account creation"""
        account_id = account_aggregate.create_account("TEST-001")
        account = account_aggregate.get_account(account_id)
        
        assert account is not None
        assert account.account_number == "TEST-001"
        assert account.balance == 0.0
        assert account.version == 1
    
    def test_deposit_and_withdrawal(self, account_aggregate):
        """Test deposit and withdrawal operations"""
        account_id = account_aggregate.create_account("TEST-002")
        
        # Deposit money
        account_aggregate.deposit(account_id, 100.0, "Initial deposit")
        account = account_aggregate.get_account(account_id)
        assert account.balance == 100.0
        assert account.version == 2
        
        # Withdraw money
        account_aggregate.withdraw(account_id, 30.0, "ATM withdrawal")
        account = account_aggregate.get_account(account_id)
        assert account.balance == 70.0
        assert account.version == 3
    
    def test_insufficient_funds(self, account_aggregate):
        """Test insufficient funds protection"""
        account_id = account_aggregate.create_account("TEST-003")
        account_aggregate.deposit(account_id, 50.0)
        
        with pytest.raises(ValueError, match="Insufficient funds"):
            account_aggregate.withdraw(account_id, 100.0)
    
    def test_temporal_queries(self, account_aggregate, event_store):
        """Test temporal queries - state at specific points in time"""
        account_id = account_aggregate.create_account("TEST-004")
        
        # Record timestamp after account creation
        t1 = datetime.now()
        
        # First deposit
        account_aggregate.deposit(account_id, 100.0)
        t2 = datetime.now()  # After first deposit
        
        # Second deposit  
        account_aggregate.deposit(account_id, 50.0)
        t3 = datetime.now()  # After second deposit
        
        # Withdrawal
        account_aggregate.withdraw(account_id, 25.0)
        
        # Query state at different times
        state_at_t1 = account_aggregate.get_account(account_id, t1)
        state_at_t2 = account_aggregate.get_account(account_id, t2)
        state_at_t3 = account_aggregate.get_account(account_id, t3)
        current_state = account_aggregate.get_account(account_id)
        
        # Verify temporal accuracy
        assert state_at_t1.balance == 0.0  # Just after creation
        assert state_at_t2.balance == 100.0  # After first deposit
        assert state_at_t3.balance == 150.0  # After second deposit
        assert current_state.balance == 125.0  # After withdrawal
    
    def test_event_ordering(self, event_store):
        """Test that events maintain proper ordering"""
        account_id = "test-account"
        
        # Create events in sequence
        events = [
            Event("e1", account_id, EventType.ACCOUNT_CREATED, {"account_number": "TEST"}, datetime.now(), 1),
            Event("e2", account_id, EventType.DEPOSIT, {"amount": 100}, datetime.now(), 2),
            Event("e3", account_id, EventType.WITHDRAWAL, {"amount": 50}, datetime.now(), 3)
        ]
        
        for event in events:
            event_store.append_event(event)
        
        # Retrieve and verify ordering
        retrieved_events = event_store.get_events(account_id)
        assert len(retrieved_events) == 3
        assert [e.version for e in retrieved_events] == [1, 2, 3]
    
    def test_optimistic_concurrency(self, event_store):
        """Test optimistic concurrency control"""
        account_id = "test-account"
        
        # Create initial event
        event1 = Event("e1", account_id, EventType.ACCOUNT_CREATED, {"account_number": "TEST"}, datetime.now(), 1)
        event_store.append_event(event1)
        
        # Try to append event with wrong version (should fail)
        event2 = Event("e2", account_id, EventType.DEPOSIT, {"amount": 100}, datetime.now(), 3)  # Wrong version
        
        with pytest.raises(ValueError, match="Concurrency conflict"):
            event_store.append_event(event2)

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
