#!/usr/bin/env python3
"""
Zero-Downtime Database Migration Router

This implementation provides a production-ready migration router that can gradually
shift traffic between databases while maintaining data consistency and safety.

Key Features:
- Gradual traffic migration with feature flags
- Real-time health monitoring and automatic rollback
- Data consistency validation
- Comprehensive metrics collection
- Circuit breaker pattern for safety
"""

import asyncio
import hashlib
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, Callable
from dataclasses import dataclass
from enum import Enum
import json


class DatabaseType(Enum):
    LEGACY = "legacy"
    NEW = "new"


class MigrationState(Enum):
    NOT_STARTED = "not_started"
    DUAL_WRITE = "dual_write"
    READ_MIGRATION = "read_migration"
    COMPLETED = "completed"
    ROLLBACK = "rollback"


@dataclass
class MigrationConfig:
    """Configuration for migration behavior and safety thresholds"""
    # Traffic percentage to route to new database (0-100)
    new_db_percentage: int = 0
    
    # Safety thresholds that trigger automatic rollback
    max_error_rate: float = 0.01  # 1% error rate threshold
    max_latency_ms: int = 500     # 500ms latency threshold
    max_inconsistency_rate: float = 0.001  # 0.1% data inconsistency threshold
    
    # Circuit breaker settings
    circuit_breaker_threshold: int = 5  # Failures before opening circuit
    circuit_breaker_timeout: int = 30   # Seconds to wait before retry
    
    # Monitoring settings
    health_check_interval: int = 10  # Seconds between health checks
    metrics_window: int = 300        # 5-minute rolling window for metrics


@dataclass
class HealthMetrics:
    """Health metrics for monitoring database performance"""
    error_count: int = 0
    total_requests: int = 0
    avg_latency_ms: float = 0.0
    inconsistency_count: int = 0
    timestamp: datetime = None
    
    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now()
    
    @property
    def error_rate(self) -> float:
        """Calculate error rate as percentage"""
        return (self.error_count / max(self.total_requests, 1)) * 100
    
    @property
    def inconsistency_rate(self) -> float:
        """Calculate data inconsistency rate as percentage"""
        return (self.inconsistency_count / max(self.total_requests, 1)) * 100


class CircuitBreaker:
    """Circuit breaker implementation to prevent cascading failures"""
    
    def __init__(self, failure_threshold: int = 5, timeout: int = 30):
        self.failure_threshold = failure_threshold
        self.timeout = timeout
        self.failure_count = 0
        self.last_failure_time = None
        self.state = "closed"  # closed, open, half-open
    
    def can_execute(self) -> bool:
        """Check if requests can be executed through this circuit"""
        if self.state == "closed":
            return True
        elif self.state == "open":
            if time.time() - self.last_failure_time > self.timeout:
                self.state = "half-open"
                return True
            return False
        else:  # half-open
            return True
    
    def record_success(self):
        """Record successful operation"""
        if self.state == "half-open":
            self.state = "closed"
        self.failure_count = 0
    
    def record_failure(self):
        """Record failed operation"""
        self.failure_count += 1
        self.last_failure_time = time.time()
        
        if self.failure_count >= self.failure_threshold:
            self.state = "open"


class DatabaseMigrationRouter:
    """
    Main migration router that handles traffic distribution and safety monitoring
    
    This router implements the gradual migration pattern with comprehensive
    safety mechanisms including health monitoring, automatic rollback, and
    circuit breaker protection.
    """
    
    def __init__(self, config: MigrationConfig):
        self.config = config
        self.state = MigrationState.NOT_STARTED
        self.circuit_breakers = {
            DatabaseType.LEGACY: CircuitBreaker(config.circuit_breaker_threshold, config.circuit_breaker_timeout),
            DatabaseType.NEW: CircuitBreaker(config.circuit_breaker_threshold, config.circuit_breaker_timeout)
        }
        
        # Metrics storage with rolling window
        self.metrics_history = {
            DatabaseType.LEGACY: [],
            DatabaseType.NEW: []
        }
        
        self.logger = logging.getLogger(__name__)
        self._setup_logging()
        
        # Mock database connections (replace with actual database clients)
        self.databases = {
            DatabaseType.LEGACY: self._create_mock_database("legacy"),
            DatabaseType.NEW: self._create_mock_database("new")
        }
    
    def _setup_logging(self):
        """Configure comprehensive logging for migration monitoring"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('migration.log'),
                logging.StreamHandler()
            ]
        )
    
    def _create_mock_database(self, db_type: str):
        """Create mock database connection (replace with actual database clients)"""
        class MockDatabase:
            def __init__(self, db_type):
                self.db_type = db_type
                self.latency_base = 50 if db_type == "new" else 100  # New DB is faster
            
            async def execute_query(self, query: str) -> Dict[str, Any]:
                # Simulate database query with realistic latency
                latency = self.latency_base + (time.time() % 10) * 5
                await asyncio.sleep(latency / 1000)  # Convert to seconds
                
                # Simulate occasional errors for testing
                if time.time() % 100 < 1:  # 1% error rate
                    raise Exception(f"Database error in {self.db_type}")
                
                return {
                    "result": f"Query executed on {self.db_type} database",
                    "latency_ms": latency,
                    "timestamp": datetime.now().isoformat()
                }
        
        return MockDatabase(db_type)
    
    def should_use_new_database(self, user_id: str) -> bool:
        """
        Determine if a request should be routed to the new database
        
        Uses consistent hashing to ensure same users always get same routing
        during the migration phase, preventing user experience inconsistencies.
        """
        if self.config.new_db_percentage == 0:
            return False
        if self.config.new_db_percentage == 100:
            return True
        
        # Use consistent hashing based on user ID
        hash_value = int(hashlib.md5(user_id.encode()).hexdigest(), 16)
        user_percentage = hash_value % 100
        
        return user_percentage < self.config.new_db_percentage
    
    async def execute_query(self, query: str, user_id: str) -> Dict[str, Any]:
        """
        Execute database query with intelligent routing and safety checks
        
        This is the main entry point that handles all the migration logic,
        including routing decisions, dual writes, consistency checks, and
        automatic rollback if issues are detected.
        """
        start_time = time.time()
        
        try:
            # Determine routing based on migration state and configuration
            use_new_db = self.should_use_new_database(user_id)
            target_db = DatabaseType.NEW if use_new_db else DatabaseType.LEGACY
            
            # Check circuit breaker before proceeding
            if not self.circuit_breakers[target_db].can_execute():
                self.logger.warning(f"Circuit breaker open for {target_db.value}, falling back")
                target_db = DatabaseType.LEGACY if target_db == DatabaseType.NEW else DatabaseType.NEW
            
            # Execute query based on migration state
            if self.state == MigrationState.DUAL_WRITE:
                result = await self._execute_dual_write(query, user_id)
            elif self.state == MigrationState.READ_MIGRATION:
                result = await self._execute_with_read_migration(query, user_id, target_db)
            else:
                result = await self._execute_single_database(query, target_db)
            
            # Record successful operation
            self.circuit_breakers[target_db].record_success()
            await self._record_metrics(target_db, True, time.time() - start_time)
            
            return result
            
        except Exception as e:
            # Record failure and handle rollback if needed
            self.circuit_breakers[target_db].record_failure()
            await self._record_metrics(target_db, False, time.time() - start_time)
            
            self.logger.error(f"Query execution failed: {str(e)}")
            
            # Attempt fallback to other database
            fallback_db = DatabaseType.LEGACY if target_db == DatabaseType.NEW else DatabaseType.NEW
            if self.circuit_breakers[fallback_db].can_execute():
                try:
                    result = await self._execute_single_database(query, fallback_db)
                    self.logger.info(f"Successfully failed over to {fallback_db.value}")
                    return result
                except Exception as fallback_error:
                    self.logger.error(f"Fallback also failed: {str(fallback_error)}")
            
            raise e
    
    async def _execute_dual_write(self, query: str, user_id: str) -> Dict[str, Any]:
        """
        Execute query with dual writes to both databases
        
        This is critical during the initial migration phase where we need
        to ensure both databases stay in sync while building confidence
        in the new system.
        """
        # Write to legacy database first (primary)
        legacy_result = await self.databases[DatabaseType.LEGACY].execute_query(query)
        
        try:
            # Write to new database (secondary)
            new_result = await self.databases[DatabaseType.NEW].execute_query(query)
            
            # Validate consistency between results
            if not await self._validate_consistency(legacy_result, new_result):
                self.logger.warning("Data consistency issue detected during dual write")
                await self._record_inconsistency(user_id, query, legacy_result, new_result)
            
        except Exception as e:
            self.logger.error(f"New database write failed during dual write: {str(e)}")
            # Continue with legacy result, but log the failure
        
        return legacy_result
    
    async def _execute_with_read_migration(self, query: str, user_id: str, target_db: DatabaseType) -> Dict[str, Any]:
        """
        Execute query during read migration phase
        
        Reads come from the target database, but writes still go to both.
        This phase tests the new database under read load while maintaining
        write consistency.
        """
        if self._is_write_operation(query):
            return await self._execute_dual_write(query, user_id)
        else:
            # Read from target database
            return await self.databases[target_db].execute_query(query)
    
    async def _execute_single_database(self, query: str, target_db: DatabaseType) -> Dict[str, Any]:
        """Execute query on single database (either legacy or new)"""
        return await self.databases[target_db].execute_query(query)
    
    def _is_write_operation(self, query: str) -> bool:
        """Determine if query is a write operation"""
        write_keywords = ['INSERT', 'UPDATE', 'DELETE', 'CREATE', 'ALTER', 'DROP']
        return any(keyword in query.upper() for keyword in write_keywords)
    
    async def _validate_consistency(self, legacy_result: Dict[str, Any], new_result: Dict[str, Any]) -> bool:
        """
        Validate consistency between database results
        
        This is a simplified version - in production, you'd implement
        more sophisticated consistency checks based on your data model.
        """
        # Simple consistency check (customize based on your needs)
        return legacy_result.get("result") == new_result.get("result")
    
    async def _record_inconsistency(self, user_id: str, query: str, legacy_result: Dict, new_result: Dict):
        """Record data inconsistency for analysis and alerting"""
        inconsistency_record = {
            "timestamp": datetime.now().isoformat(),
            "user_id": user_id,
            "query": query,
            "legacy_result": legacy_result,
            "new_result": new_result
        }
        
        # In production, send this to your monitoring system
        self.logger.error(f"Data inconsistency detected: {json.dumps(inconsistency_record)}")
    
    async def _record_metrics(self, db_type: DatabaseType, success: bool, latency_seconds: float):
        """Record performance metrics for monitoring and alerting"""
        current_metrics = HealthMetrics(
            error_count=0 if success else 1,
            total_requests=1,
            avg_latency_ms=latency_seconds * 1000,
            inconsistency_count=0,  # Set separately by consistency checker
            timestamp=datetime.now()
        )
        
        # Add to rolling window
        self.metrics_history[db_type].append(current_metrics)
        
        # Keep only recent metrics (rolling window)
        cutoff_time = datetime.now() - timedelta(seconds=self.config.metrics_window)
        self.metrics_history[db_type] = [
            m for m in self.metrics_history[db_type] if m.timestamp > cutoff_time
        ]
    
    async def health_check(self) -> Dict[str, Any]:
        """
        Comprehensive health check that monitors system state and triggers
        automatic actions if safety thresholds are exceeded
        """
        health_status = {
            "timestamp": datetime.now().isoformat(),
            "migration_state": self.state.value,
            "new_db_percentage": self.config.new_db_percentage,
            "databases": {}
        }
        
        for db_type in [DatabaseType.LEGACY, DatabaseType.NEW]:
            metrics = self._calculate_aggregate_metrics(db_type)
            circuit_state = self.circuit_breakers[db_type].state
            
            health_status["databases"][db_type.value] = {
                "circuit_breaker_state": circuit_state,
                "error_rate": metrics.error_rate,
                "avg_latency_ms": metrics.avg_latency_ms,
                "inconsistency_rate": metrics.inconsistency_rate,
                "total_requests": metrics.total_requests
            }
            
            # Check if automatic rollback is needed
            if await self._should_trigger_rollback(metrics):
                self.logger.critical(f"Safety thresholds exceeded for {db_type.value}, triggering rollback")
                await self.trigger_rollback(f"Safety thresholds exceeded: {metrics}")
        
        return health_status
    
    def _calculate_aggregate_metrics(self, db_type: DatabaseType) -> HealthMetrics:
        """Calculate aggregate metrics from rolling window"""
        recent_metrics = self.metrics_history[db_type]
        
        if not recent_metrics:
            return HealthMetrics()
        
        total_errors = sum(m.error_count for m in recent_metrics)
        total_requests = sum(m.total_requests for m in recent_metrics)
        total_inconsistencies = sum(m.inconsistency_count for m in recent_metrics)
        avg_latency = sum(m.avg_latency_ms for m in recent_metrics) / len(recent_metrics)
        
        return HealthMetrics(
            error_count=total_errors,
            total_requests=total_requests,
            avg_latency_ms=avg_latency,
            inconsistency_count=total_inconsistencies,
            timestamp=datetime.now()
        )
    
    async def _should_trigger_rollback(self, metrics: HealthMetrics) -> bool:
        """Determine if automatic rollback should be triggered"""
        return (
            metrics.error_rate > self.config.max_error_rate or
            metrics.avg_latency_ms > self.config.max_latency_ms or
            metrics.inconsistency_rate > self.config.max_inconsistency_rate
        )
    
    async def trigger_rollback(self, reason: str):
        """
        Trigger automatic rollback to previous safe state
        
        This is a critical safety mechanism that can save your system
        when things go wrong during migration.
        """
        self.logger.critical(f"ROLLBACK TRIGGERED: {reason}")
        
        # Reset to safe configuration
        self.config.new_db_percentage = 0
        self.state = MigrationState.ROLLBACK
        
        # Reset circuit breakers
        for cb in self.circuit_breakers.values():
            cb.failure_count = 0
            cb.state = "closed"
        
        # Send alert to operations team
        await self._send_alert(f"Database migration rollback triggered: {reason}")
    
    async def _send_alert(self, message: str):
        """Send alert to monitoring system (implement with your alerting system)"""
        alert = {
            "timestamp": datetime.now().isoformat(),
            "severity": "critical",
            "service": "database-migration",
            "message": message
        }
        
        # In production, integrate with PagerDuty, Slack, etc.
        self.logger.critical(f"ALERT: {json.dumps(alert)}")
    
    async def update_migration_percentage(self, new_percentage: int):
        """
        Safely update migration percentage with validation
        
        This allows for gradual rollout control during migration.
        """
        if not 0 <= new_percentage <= 100:
            raise ValueError("Percentage must be between 0 and 100")
        
        old_percentage = self.config.new_db_percentage
        self.config.new_db_percentage = new_percentage
        
        self.logger.info(f"Migration percentage updated: {old_percentage}% -> {new_percentage}%")
        
        # Update migration state based on percentage
        if new_percentage == 0:
            self.state = MigrationState.NOT_STARTED
        elif new_percentage < 100:
            self.state = MigrationState.READ_MIGRATION
        else:
            self.state = MigrationState.COMPLETED


# Example usage and testing
async def main():
    """
    Example usage showing how to use the migration router
    """
    # Initialize configuration
    config = MigrationConfig(
        new_db_percentage=10,  # Start with 10% of traffic
        max_error_rate=0.01,   # 1% error threshold
        max_latency_ms=500,    # 500ms latency threshold
    )
    
    # Create migration router
    router = DatabaseMigrationRouter(config)
    
    # Simulate some queries
    for i in range(10):
        user_id = f"user_{i}"
        query = f"SELECT * FROM users WHERE id = {i}"
        
        try:
            result = await router.execute_query(query, user_id)
            print(f"Query {i}: Success - {result['result']}")
        except Exception as e:
            print(f"Query {i}: Failed - {str(e)}")
    
    # Check system health
    health = await router.health_check()
    print(f"\nSystem Health: {json.dumps(health, indent=2)}")
    
    # Gradually increase migration percentage
    await router.update_migration_percentage(25)
    print("Migration percentage increased to 25%")


if __name__ == "__main__":
    asyncio.run(main())