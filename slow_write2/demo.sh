#!/bin/bash
# Executable Blueprint for Asynchronous Logging (Python)

# --- Prerequisite Checks ---
echo "--- 1. Checking Prerequisites (Python and Bash) ---"
command -v python3 >/dev/null 2>&1 || { echo >&2 "Error: python3 is required but not installed. Aborting."; exit 1; }
echo "Prerequisites OK."

# --- Environment Setup and Code Generation ---
PROJECT_DIR="async_logger_lesson"
LOG_FILE="application.log"

# Save the original directory
ORIGINAL_DIR=$(pwd)

echo "--- 2. Creating Project Structure and Files ---"
mkdir -p "$PROJECT_DIR" || { echo >&2 "Error: Failed to create project directory. Aborting."; exit 1; }
cd "$PROJECT_DIR" || { echo >&2 "Error: Failed to change to project directory. Aborting."; exit 1; }

# Create the main application file with the Asynchronous Logger
cat << 'EOF' > async_app.py
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

EOF

# --- Build Process and Automated Testing ---
echo "--- 3. Executing the Lesson Application ---"
python3 async_app.py

# --- Success Report (via the python script's output) ---
echo "--- 6. Cleanup ---"
cd "$ORIGINAL_DIR" || exit 1
echo "Lesson complete. Directory: $PROJECT_DIR"