import unittest
import asyncio
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.main import FanOutManager, User, Message

class TestFanOutPatterns(unittest.TestCase):
    def setUp(self):
        self.manager = FanOutManager()
        self.manager.add_user('test_user', 1000)
        self.manager.add_user('celebrity_user', 50000)
    
    def test_user_tier_assignment(self):
        """Test that users are assigned correct tiers based on follower count"""
        regular_user = self.manager.users['test_user']
        celebrity_user = self.manager.users['celebrity_user']
        
        self.assertEqual(regular_user.tier, 'regular')
        self.assertEqual(celebrity_user.tier, 'celebrity')
    
    def test_fanout_strategy_selection(self):
        """Test that appropriate fanout strategy is selected for different user tiers"""
        regular_user = self.manager.users['test_user']
        celebrity_user = self.manager.users['celebrity_user']
        
        # Regular users should use write fanout
        self.assertTrue(self.manager.should_use_write_fanout(regular_user))
        
        # Celebrities should use read fanout
        self.assertFalse(self.manager.should_use_write_fanout(celebrity_user))
    
    def test_back_pressure_handling(self):
        """Test that system switches to read fanout under high load"""
        # Fill queue to trigger back pressure
        self.manager.message_queue = ['msg'] * 1500  # Exceed threshold
        
        regular_user = self.manager.users['test_user']
        
        # Should switch to read fanout under back pressure
        self.assertFalse(self.manager.should_use_write_fanout(regular_user))
    
    async def test_fanout_on_write_processing(self):
        """Test fanout on write message processing"""
        message = Message(
            id='test_msg_1',
            user_id='test_user',
            content='Test message',
            timestamp=1234567890.0,
            fanout_strategy='write'
        )
        
        result = await self.manager.fanout_on_write(message)
        
        self.assertEqual(result['strategy'], 'fanout_on_write')
        self.assertGreater(result['notifications_created'], 0)
        self.assertGreater(result['processing_time'], 0)
    
    async def test_fanout_on_read_processing(self):
        """Test fanout on read feed generation"""
        result = await self.manager.fanout_on_read('test_user')
        
        self.assertEqual(result['strategy'], 'fanout_on_read')
        self.assertIsInstance(result['feed_items'], list)
        self.assertGreater(result['processing_time'], 0)

def run_async_test(test_func):
    """Helper to run async test functions"""
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        loop.run_until_complete(test_func())
    finally:
        loop.close()

if __name__ == '__main__':
    # Run async tests
    test_case = TestFanOutPatterns()
    test_case.setUp()
    
    print("Running Fan-Out Architecture Tests...")
    
    # Run sync tests
    test_case.test_user_tier_assignment()
    print("✓ User tier assignment test passed")
    
    test_case.test_fanout_strategy_selection()
    print("✓ Fanout strategy selection test passed")
    
    test_case.test_back_pressure_handling()
    print("✓ Back pressure handling test passed")
    
    # Run async tests
    run_async_test(test_case.test_fanout_on_write_processing)
    print("✓ Fanout on write processing test passed")
    
    run_async_test(test_case.test_fanout_on_read_processing)
    print("✓ Fanout on read processing test passed")
    
    print("\nAll tests passed! ✨")
