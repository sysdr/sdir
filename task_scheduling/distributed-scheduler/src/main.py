import os
import sys

# Simple script to route to appropriate service based on NODE_TYPE
node_type = os.getenv("NODE_TYPE", "scheduler")

if node_type == "scheduler":
    import subprocess
    subprocess.run([sys.executable, "src/scheduler.py"])
elif node_type == "worker":
    import subprocess
    subprocess.run([sys.executable, "src/worker.py"])
else:
    print(f"Unknown node type: {node_type}")
    sys.exit(1)
