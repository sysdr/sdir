import threading
import time
import random
from datetime import datetime, timedelta
from dataclasses import dataclass, field
from typing import List, Dict, Any, Optional
import logging
from sqlalchemy import create_engine, text, pool as sa_pool, event
from sqlalchemy.exc import TimeoutError, DatabaseError
import concurrent.futures
from contextlib import contextmanager

logger = logging.getLogger(__name__)

@dataclass
class PoolMetrics:
    """Metrics for connection pool monitoring"""
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())
    pool_size: int = 0
    checked_out: int = 0
    available: int = 0
    queue_size: int = 0
    total_connections_created: int = 0
    total_connections_closed: int = 0
    current_overflow: int = 0
    avg_response_time_ms: float = 0.0
    error_rate_percent: float = 0.0
    pool_utilization_percent: float = 0.0
    connections_per_second: float = 0.0
    active_scenarios: List[str] = field(default_factory=list)

@dataclass
class QueryResult:
    """Result of a database query execution"""
    success: bool
    duration_ms: float
    error: Optional[str] = None
    connection_id: Optional[str] = None

class ConnectionPoolManager:
    """Manages database connection pool and provides monitoring capabilities"""
    
    def __init__(self, database_url: str, max_pool_size: int = 10, 
                 min_pool_size: int = 2, pool_timeout: int = 30):
        self.database_url = database_url
        self.max_pool_size = max_pool_size
        self.min_pool_size = min_pool_size
        self.pool_timeout = pool_timeout
        
        # Metrics tracking
        self.metrics_lock = threading.Lock()
        self.total_connections_created = 0
        self.total_connections_closed = 0
        self.recent_response_times = []
        self.recent_errors = []
        self.active_scenarios = []
        
        # Create engine with connection pooling
        self._create_engine()
        self._setup_database()
        
    def _create_engine(self):
        """Create SQLAlchemy engine with custom pool configuration"""
        try:
            self.engine = create_engine(
                self.database_url,
                poolclass=sa_pool.QueuePool,
                pool_size=self.min_pool_size,
                max_overflow=self.max_pool_size - self.min_pool_size,
                pool_timeout=self.pool_timeout,
                pool_recycle=3600,  # Recycle connections every hour
                pool_pre_ping=True,  # Verify connections before use
                echo=False  # Set to True for SQL logging
            )
            
            # Add event listeners to track connection lifecycle
            @event.listens_for(self.engine, "connect")
            def connection_created(dbapi_connection, connection_record):
                with self.metrics_lock:
                    self.total_connections_created += 1
                    logger.debug(f"Connection created. Total created: {self.total_connections_created}")
            
            @event.listens_for(self.engine, "close")
            def connection_closed(dbapi_connection, connection_record):
                with self.metrics_lock:
                    self.total_connections_closed += 1
                    logger.debug(f"Connection closed. Total closed: {self.total_connections_closed}")
            
            @event.listens_for(self.engine, "checkout")
            def connection_checked_out(dbapi_connection, connection_record, connection_proxy):
                logger.debug("Connection checked out from pool")
            
            @event.listens_for(self.engine, "checkin")
            def connection_checked_in(dbapi_connection, connection_record):
                logger.debug("Connection checked in to pool")
            
            logger.info(f"Engine created with pool_size={self.min_pool_size}, max_overflow={self.max_pool_size - self.min_pool_size}")
        except Exception as e:
            logger.error(f"Failed to create engine: {e}")
            raise
    
    def _setup_database(self):
        """Setup demo database tables"""
        try:
            with self.engine.connect() as conn:
                # Create demo table for testing
                conn.execute(text("""
                    CREATE TABLE IF NOT EXISTS demo_data (
                        id SERIAL PRIMARY KEY,
                        data TEXT,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """))
                
                # Insert some demo data if table is empty
                result = conn.execute(text("SELECT COUNT(*) FROM demo_data"))
                count = result.scalar()
                
                if count == 0:
                    for i in range(100):
                        conn.execute(text(
                            "INSERT INTO demo_data (data) VALUES (:data)"
                        ), {"data": f"Demo record {i}"})
                
                conn.commit()
                logger.info("Database setup completed")
                
        except Exception as e:
            logger.error(f"Database setup failed: {e}")
            raise
    
    def test_connection(self) -> bool:
        """Test if database connection is working"""
        try:
            with self.engine.connect() as conn:
                conn.execute(text("SELECT 1"))
                return True
        except Exception as e:
            logger.error(f"Connection test failed: {e}")
            return False
    
    def execute_query(self, query: str, params: Dict[str, Any] = None, 
                     timeout: float = 10.0) -> QueryResult:
        """Execute a database query and track metrics"""
        start_time = time.time()
        
        try:
            with self.engine.connect() as conn:
                if params:
                    result = conn.execute(text(query), params)
                else:
                    result = conn.execute(text(query))
                
                # Simulate processing time for some queries
                if "slow" in query.lower():
                    time.sleep(random.uniform(1, 3))
                
                duration_ms = (time.time() - start_time) * 1000
                
                # Track metrics
                with self.metrics_lock:
                    self.recent_response_times.append(duration_ms)
                    if len(self.recent_response_times) > 100:
                        self.recent_response_times.pop(0)
                
                return QueryResult(
                    success=True,
                    duration_ms=duration_ms,
                    connection_id=str(id(conn))
                )
                
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            
            # Track error
            with self.metrics_lock:
                self.recent_errors.append(datetime.now())
                if len(self.recent_errors) > 100:
                    self.recent_errors.pop(0)
            
            logger.error(f"Query execution failed: {e}")
            return QueryResult(
                success=False,
                duration_ms=duration_ms,
                error=str(e)
            )
    
    def get_metrics(self) -> PoolMetrics:
        """Get current pool metrics"""
        try:
            # Get pool statistics
            pool = self.engine.pool
            
            with self.metrics_lock:
                # Calculate average response time
                avg_response_time = (
                    sum(self.recent_response_times) / len(self.recent_response_times)
                    if self.recent_response_times else 0.0
                )
                
                # Calculate error rate (errors in last minute)
                recent_errors_count = len([
                    err for err in self.recent_errors
                    if err > datetime.now() - timedelta(minutes=1)
                ])
                
                total_requests = len(self.recent_response_times) + recent_errors_count
                error_rate = (recent_errors_count / total_requests * 100) if total_requests > 0 else 0.0
                
                # Pool utilization
                checked_out = pool.checkedout()
                pool_size = pool.size()
                utilization = (checked_out / self.max_pool_size * 100) if self.max_pool_size > 0 else 0.0
                
                return PoolMetrics(
                    pool_size=pool_size,
                    checked_out=checked_out,
                    available=pool_size - checked_out,
                    queue_size=max(0, pool.checkedin() - pool_size),
                    total_connections_created=self.total_connections_created,
                    total_connections_closed=self.total_connections_closed,
                    current_overflow=max(0, pool_size - self.min_pool_size),
                    avg_response_time_ms=avg_response_time,
                    error_rate_percent=error_rate,
                    pool_utilization_percent=utilization,
                    connections_per_second=0.0,  # TODO: Calculate this
                    active_scenarios=self.active_scenarios.copy()
                )
                
        except Exception as e:
            logger.error(f"Error getting metrics: {e}")
            return PoolMetrics()
    
    def simulate_normal_load(self) -> Dict[str, Any]:
        """Simulate normal application load"""
        self.active_scenarios.append("normal_load")
        
        def worker():
            for _ in range(10):
                query = "SELECT * FROM demo_data ORDER BY RANDOM() LIMIT 5"
                result = self.execute_query(query)
                time.sleep(random.uniform(0.1, 0.5))
        
        # Start multiple workers
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(worker) for _ in range(3)]
            concurrent.futures.wait(futures)
        
        if "normal_load" in self.active_scenarios:
            self.active_scenarios.remove("normal_load")
            
        return {"message": "Normal load simulation completed", "workers": 3, "queries_per_worker": 10}
    
    def simulate_high_load(self) -> Dict[str, Any]:
        """Simulate high application load"""
        self.active_scenarios.append("high_load")
        
        def worker():
            for _ in range(20):
                query = "SELECT COUNT(*) FROM demo_data WHERE data LIKE '%Demo%'"
                result = self.execute_query(query)
                time.sleep(random.uniform(0.05, 0.2))
        
        # Start many workers to stress the pool
        with concurrent.futures.ThreadPoolExecutor(max_workers=15) as executor:
            futures = [executor.submit(worker) for _ in range(8)]
            concurrent.futures.wait(futures)
        
        if "high_load" in self.active_scenarios:
            self.active_scenarios.remove("high_load")
            
        return {"message": "High load simulation completed", "workers": 8, "queries_per_worker": 20}
    
    def simulate_pool_exhaustion(self) -> Dict[str, Any]:
        """Simulate pool exhaustion scenario"""
        self.active_scenarios.append("pool_exhaustion")
        
        def long_running_worker():
            # Execute long-running queries that hold connections
            query = "SELECT pg_sleep(5)"  # Sleep for 5 seconds
            result = self.execute_query(query, timeout=10)
        
        # Start more workers than pool can handle
        with concurrent.futures.ThreadPoolExecutor(max_workers=self.max_pool_size + 5) as executor:
            futures = [executor.submit(long_running_worker) for _ in range(self.max_pool_size + 3)]
            concurrent.futures.wait(futures, timeout=30)
        
        if "pool_exhaustion" in self.active_scenarios:
            self.active_scenarios.remove("pool_exhaustion")
            
        return {
            "message": "Pool exhaustion simulation completed",
            "workers": self.max_pool_size + 3,
            "expected_timeouts": 3
        }
    
    def simulate_connection_leaks(self) -> Dict[str, Any]:
        """Simulate connection leak scenario"""
        self.active_scenarios.append("connection_leaks")
        
        # This would normally be implemented by not properly closing connections
        # For demo purposes, we'll simulate by creating many short-lived connections
        for _ in range(20):
            try:
                conn = self.engine.connect()
                result = conn.execute(text("SELECT 1"))
                # Intentionally delay closing to simulate leak
                time.sleep(0.1)
                conn.close()
            except Exception as e:
                logger.error(f"Connection leak simulation error: {e}")
        
        if "connection_leaks" in self.active_scenarios:
            self.active_scenarios.remove("connection_leaks")
            
        return {"message": "Connection leak simulation completed", "leaked_connections": 0}
    
    def simulate_database_slowness(self) -> Dict[str, Any]:
        """Simulate database slowness"""
        self.active_scenarios.append("database_slowness")
        
        def slow_worker():
            for _ in range(5):
                # Execute slow queries
                query = "SELECT pg_sleep(2)"  # 2 second delay
                result = self.execute_query(query, timeout=10)
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            futures = [executor.submit(slow_worker) for _ in range(3)]
            concurrent.futures.wait(futures)
        
        if "database_slowness" in self.active_scenarios:
            self.active_scenarios.remove("database_slowness")
            
        return {"message": "Database slowness simulation completed", "slow_queries": 15}
    
    def close(self):
        """Close the connection pool"""
        try:
            self.engine.dispose()
            logger.info("Connection pool closed")
        except Exception as e:
            logger.error(f"Error closing pool: {e}")
