# Autoscaling Demo - Local Setup

This guide shows you how to run the autoscaling demo locally without Docker.

## 🚀 Quick Start

### Start the Demo
```bash
./startlocal.sh
```

### Stop the Demo
```bash
./stoplocal.sh
```

## 📋 Prerequisites

- **Python 3.8+** - The demo uses Python 3
- **pip3** - Python package manager
- **Redis** - For data storage (will be started automatically via Homebrew)
- **Homebrew** - For managing Redis service

## 🔧 What the Scripts Do

### `startlocal.sh`
1. **Checks Dependencies** - Verifies Python3 and pip3 are installed
2. **Installs Packages** - Installs all required Python packages from `requirements.txt`
3. **Starts Redis** - Starts Redis service if not already running
4. **Finds Available Port** - Automatically finds an available port (starts with 3000)
5. **Configures Flask** - Updates the Flask app to use the available port
6. **Starts Application** - Launches the Flask application with proper configuration
7. **Verifies Startup** - Checks that the application is responding correctly

### `stoplocal.sh`
1. **Stops Flask App** - Gracefully stops the Flask application
2. **Cleans Up Processes** - Kills any remaining Python processes
3. **Removes Temp Files** - Cleans up temporary configuration files
4. **Port Verification** - Confirms ports are free

## 🌐 Accessing the Demo

Once started, you can access:

- **Web Interface**: http://localhost:[PORT] (port will be shown in startup)
- **API Status**: http://localhost:[PORT]/api/status
- **API Endpoints**:
  - `GET /api/status` - Current system status
  - `POST /api/start` - Start the autoscaling engine
  - `POST /api/stop` - Stop the autoscaling engine
  - `POST /api/load_pattern` - Change load simulation pattern

## 📊 Features

The demo showcases three autoscaling algorithms:

1. **Reactive Autoscaler** - Traditional threshold-based scaling
2. **Predictive Autoscaler** - ML-based predictive scaling
3. **Hybrid Autoscaler** - Combines both approaches

### Load Patterns
- **Steady** - Consistent baseline load
- **Spike** - Sudden traffic spikes
- **Gradual** - Gradual load increase
- **Oscillating** - Wave-like load patterns
- **Chaos** - Random load variations

## 🛠️ Troubleshooting

### Port Already in Use
The script automatically finds an available port. If you see port conflicts, the script will try the next available port.

### Redis Issues
If Redis fails to start:
```bash
brew services restart redis
```

### Python Dependencies
If you get import errors:
```bash
pip3 install -r requirements.txt
```

### Permission Issues
Make sure the scripts are executable:
```bash
chmod +x startlocal.sh stoplocal.sh
```

## 📁 File Structure

```
autoscaling-demo/
├── startlocal.sh          # Start script
├── stoplocal.sh           # Stop script
├── src/main.py            # Main Flask application
├── templates/index.html   # Web interface
├── static/                # Static assets
├── requirements.txt       # Python dependencies
└── README_LOCAL.md        # This file
```

## 🔍 Monitoring

### View Logs
The application logs are displayed in real-time when you run `./startlocal.sh`

### Check Status
```bash
curl http://localhost:[PORT]/api/status
```

### Process Management
- **PID File**: `.flask_pid` contains the Flask process ID
- **Port File**: `.flask_port` contains the port number
- **Auto-cleanup**: These files are automatically removed when stopping

## 🎯 Next Steps

1. **Start the demo**: `./startlocal.sh`
2. **Open the web interface** in your browser
3. **Try different load patterns** to see autoscaling in action
4. **Monitor the metrics** in real-time
5. **Stop when done**: `./stoplocal.sh`

Enjoy exploring the autoscaling demo! 🚀 