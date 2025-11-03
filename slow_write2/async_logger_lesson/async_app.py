import threading
import queue
import time
import os

# --- Configuration ---
LOG_QUEUE_MAX_SIZE = 100 # The bounded queue size for backpressure
LOG_FILE = "application.log"

# --- The Asynchronous Logger Core ---
class AsyncLogger:
    def __init__(self, log_file, max_size):
        # 1. Bounded Queue: Our fast, non-blocking buffer
        self.log_queue = queue.Queue(maxsize=max_size)
        self.log_file = log_file
        self.stop_event = threading.Event()
        self.writer_thread = threading.Thread(target=self._log_writer, daemon=True)
        self.writer_thread.start()

    def log(self, message):
        """Application's non-blocking logging interface."""
        try:
            # 2. Non-Blocking Put: Drops the message and continues immediately
            self.log_queue.put_nowait(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")
            # This 'put_nowait' is the crucial piece for performance!
        except queue.Full:
            # 3. Backpressure/Drop: Sacrifice log data for system stability
            print(f"!!! WARNING: Log queue full. Dropping log: {message[:20]}...")

    def _log_writer(self):
        """Dedicated, slow-path worker thread for blocking disk I/O."""
        print(f"Logger Writer Thread started. Writing to {self.log_file}")
        with open(self.log_file, 'a') as f:
            while not self.stop_event.is_set():
                try:
                    # Blocking get (with timeout) to wait for logs
                    log_entry = self.log_queue.get(timeout=0.1)
                    
                    # SIMULATE SLOW DISK I/O: The culprit we are decoupling from.
                    # This blocking operation only impacts the writer thread, NOT the main app!
                    time.sleep(0.01) 
                    
                    f.write(log_entry)
                    f.flush() # Force write to disk for durability check
                    self.log_queue.task_done()
                except queue.Empty:
                    # Timeout reached, continue looping
                    continue
                except Exception as e:
                    print(f"Error writing log: {e}")

    def stop(self):
        """Clean shutdown."""
        self.stop_event.set()
        self.writer_thread.join()
        print("Logger Writer Thread stopped.")

# --- Application Simulation ---
def simulate_fast_request(logger, request_id):
    """Simulates a fast-path application request."""
    start_time = time.monotonic()
    
    # 1. Critical Business Logic (Fast)
    time.sleep(0.001) 
    
    # 2. Log Call (Non-Blocking)
    logger.log(f"Request {request_id}: Processing started.")
    
    # 3. More Logic
    time.sleep(0.001) 
    
    logger.log(f"Request {request_id}: Processing finished. Time taken: {time.monotonic() - start_time:.4f}s")
    
    # The total time is dominated by logic, not the log write (0.01s), which runs in parallel!

if __name__ == "__main__":
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
        
    print("\n--- 3. Starting Asynchronous Application ---")
    logger = AsyncLogger(LOG_FILE, LOG_QUEUE_MAX_SIZE)

    # 4. Simulate a sudden spike of high-concurrency requests
    threads = []
    print(f"Spawning {LOG_QUEUE_MAX_SIZE * 3} concurrent requests to demonstrate backpressure...")
    for i in range(LOG_QUEUE_MAX_SIZE * 3):
        t = threading.Thread(target=simulate_fast_request, args=(logger, i), daemon=True)
        threads.append(t)
        t.start()
    
    # Wait for all request threads to finish
    for t in threads:
        t.join(timeout=0.5)

    print("\n--- 4. All high-speed requests finished. Critical path complete. ---")
    print(f"Waiting for Logger to empty queue... (Queue size: {logger.log_queue.qsize()})")
    
    # Give the slow writer thread a moment to catch up
    time.sleep(2) 
    
    # 5. Clean Shutdown and Report
    logger.stop()

    print("\n--- 5. Final Success Report ---")
    print(f"Log file size: {os.path.getsize(LOG_FILE)} bytes.")
    print("Application successfully handled a request spike without blocking the primary threads.")
    print("Check the 'application.log' file to see the delayed log writes.")

