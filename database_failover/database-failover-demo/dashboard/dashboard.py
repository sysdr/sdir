from flask import Flask, render_template_string, jsonify
import requests
import psycopg2

app = Flask(__name__)

def get_connection(host, port=5432):
    try:
        return psycopg2.connect(
            host=host,
            port=port,
            user='postgres',
            password='password',
            database='testdb',
            connect_timeout=3
        )
    except:
        return None

def get_node_status(host):
    conn = get_connection(host)
    if not conn:
        return {'status': 'down', 'role': 'unknown', 'lag': None, 'transactions': 0}
    
    try:
        cur = conn.cursor()
        
        # Check if in recovery
        cur.execute("SELECT pg_is_in_recovery()")
        in_recovery = cur.fetchone()[0]
        role = 'replica' if in_recovery else 'primary'
        
        # Get transaction count
        cur.execute("SELECT COUNT(*) FROM transactions")
        tx_count = cur.fetchone()[0]
        
        # Get replication lag for replicas
        lag = None
        if in_recovery:
            cur.execute("SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag")
            result = cur.fetchone()
            lag = f"{result[0]:.2f}s" if result and result[0] else "0s"
        
        cur.close()
        conn.close()
        
        return {
            'status': 'up',
            'role': role,
            'lag': lag,
            'transactions': tx_count
        }
    except Exception as e:
        return {'status': 'error', 'role': 'unknown', 'lag': None, 'transactions': 0}

@app.route('/')
def dashboard():
    return render_template_string('''
<!DOCTYPE html>
<html>
<head>
    <title>Database Failover Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            color: white;
            margin-bottom: 30px;
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
        }
        .header p {
            font-size: 1.1em;
            opacity: 0.9;
        }
        .cluster-container {
            background: white;
            border-radius: 12px;
            padding: 30px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            margin-bottom: 20px;
        }
        .nodes-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .node-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 10px;
            padding: 20px;
            color: white;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
            transition: transform 0.3s;
        }
        .node-card:hover {
            transform: translateY(-5px);
        }
        .node-card.primary {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
        }
        .node-card.down {
            background: linear-gradient(135deg, #eb3349 0%, #f45c43 100%);
        }
        .node-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }
        .node-name {
            font-size: 1.4em;
            font-weight: bold;
        }
        .role-badge {
            background: rgba(255,255,255,0.3);
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
        }
        .node-stats {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
        }
        .stat {
            background: rgba(255,255,255,0.2);
            padding: 10px;
            border-radius: 6px;
        }
        .stat-label {
            font-size: 0.85em;
            opacity: 0.9;
            margin-bottom: 5px;
        }
        .stat-value {
            font-size: 1.3em;
            font-weight: bold;
        }
        .controls {
            display: flex;
            gap: 15px;
            justify-content: center;
            flex-wrap: wrap;
        }
        .btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 15px 30px;
            border-radius: 8px;
            font-size: 1em;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
        }
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(0,0,0,0.3);
        }
        .btn.danger {
            background: linear-gradient(135deg, #eb3349 0%, #f45c43 100%);
        }
        .metrics {
            background: #f8f9fa;
            border-radius: 8px;
            padding: 20px;
            margin-top: 20px;
        }
        .metrics h3 {
            margin-bottom: 15px;
            color: #667eea;
        }
        .metric-row {
            display: flex;
            justify-content: space-between;
            padding: 10px 0;
            border-bottom: 1px solid #dee2e6;
        }
        .metric-row:last-child {
            border-bottom: none;
        }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status-up { background: #38ef7d; }
        .status-down { background: #f45c43; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🗄️ Database Failover Dashboard</h1>
            <p>Real-time Cluster Monitoring & Control</p>
        </div>
        
        <div class="cluster-container">
            <div class="nodes-grid" id="nodesGrid">
                <!-- Nodes will be inserted here -->
            </div>
            
            <div class="controls">
                <button class="btn" onclick="triggerFailover()">🔄 Trigger Manual Failover</button>
                <button class="btn danger" onclick="killPrimary()">💥 Simulate Primary Failure</button>
                <button class="btn" onclick="insertTransaction()">💳 Insert Transaction</button>
            </div>
            
            <div class="metrics">
                <h3>📊 Cluster Metrics</h3>
                <div id="metrics">
                    <!-- Metrics will be inserted here -->
                </div>
            </div>
        </div>
    </div>

    <script>
        function updateDashboard() {
            fetch('/api/cluster_status')
                .then(r => r.json())
                .then(data => {
                    const grid = document.getElementById('nodesGrid');
                    grid.innerHTML = '';
                    
                    Object.entries(data.nodes).forEach(([name, info]) => {
                        const isPrimary = name === data.cluster.primary;
                        const statusClass = info.status === 'up' ? (isPrimary ? 'primary' : '') : 'down';
                        
                        grid.innerHTML += `
                            <div class="node-card ${statusClass}">
                                <div class="node-header">
                                    <div class="node-name">
                                        <span class="status-indicator status-${info.status}"></span>
                                        ${name}
                                    </div>
                                    <div class="role-badge">${info.role.toUpperCase()}</div>
                                </div>
                                <div class="node-stats">
                                    <div class="stat">
                                        <div class="stat-label">Status</div>
                                        <div class="stat-value">${info.status}</div>
                                    </div>
                                    <div class="stat">
                                        <div class="stat-label">Transactions</div>
                                        <div class="stat-value">${info.transactions}</div>
                                    </div>
                                    ${info.lag ? `
                                    <div class="stat">
                                        <div class="stat-label">Replication Lag</div>
                                        <div class="stat-value">${info.lag}</div>
                                    </div>` : ''}
                                </div>
                            </div>
                        `;
                    });
                    
                    const metricsDiv = document.getElementById('metrics');
                    metricsDiv.innerHTML = `
                        <div class="metric-row">
                            <strong>Current Primary:</strong>
                            <span>${data.cluster.primary}</span>
                        </div>
                        <div class="metric-row">
                            <strong>Failovers Completed:</strong>
                            <span>${data.cluster.last_failover ? '1+' : '0'}</span>
                        </div>
                        <div class="metric-row">
                            <strong>Split-Brain Prevented:</strong>
                            <span>${data.cluster.split_brain_prevented}</span>
                        </div>
                        <div class="metric-row">
                            <strong>Last Failover:</strong>
                            <span>${data.cluster.last_failover || 'Never'}</span>
                        </div>
                    `;
                });
        }
        
        function triggerFailover() {
            if (confirm('Trigger manual failover?')) {
                fetch('/api/trigger_failover', {method: 'POST'})
                    .then(r => r.json())
                    .then(data => {
                        alert(data.success ? 'Failover triggered!' : 'Failover failed!');
                        updateDashboard();
                    });
            }
        }
        
        function killPrimary() {
            if (confirm('This will stop the primary database. Continue?')) {
                fetch('/api/kill_primary', {method: 'POST'})
                    .then(r => r.json())
                    .then(data => {
                        alert('Primary stopped! Monitor will detect and trigger failover...');
                    });
            }
        }
        
        function insertTransaction() {
            fetch('/api/insert_transaction', {method: 'POST'})
                .then(r => r.json())
                .then(data => {
                    alert(data.success ? 'Transaction inserted!' : 'Failed to insert transaction');
                    updateDashboard();
                });
        }
        
        // Update every 3 seconds
        updateDashboard();
        setInterval(updateDashboard, 3000);
    </script>
</body>
</html>
    ''')

@app.route('/api/cluster_status')
def cluster_status():
    nodes = {
        'primary': get_node_status('primary'),
        'replica1': get_node_status('replica1'),
        'replica2': get_node_status('replica2')
    }
    
    try:
        response = requests.get('http://orchestrator:5001/status', timeout=3)
        cluster = response.json()
    except:
        cluster = {'primary': 'primary', 'split_brain_prevented': 0, 'last_failover': None}
    
    return jsonify({'nodes': nodes, 'cluster': cluster})

@app.route('/api/trigger_failover', methods=['POST'])
def trigger_failover():
    try:
        response = requests.post('http://orchestrator:5001/trigger_failover', timeout=10)
        return response.json()
    except:
        return jsonify({'success': False})

@app.route('/api/kill_primary', methods=['POST'])
def kill_primary():
    import subprocess
    try:
        subprocess.run(['docker', 'stop', 'pg_primary'], check=True)
        return jsonify({'success': True})
    except:
        return jsonify({'success': False})

@app.route('/api/insert_transaction', methods=['POST'])
def insert_transaction():
    try:
        response = requests.get('http://orchestrator:5001/status', timeout=3)
        cluster = response.json()
        primary = cluster.get('primary', 'primary')
    except:
        primary = 'primary'
    
    conn = get_connection(primary)
    if not conn:
        return jsonify({'success': False})
    
    try:
        cur = conn.cursor()
        cur.execute("INSERT INTO transactions (amount, status) VALUES (99.99, 'completed')")
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'success': True})
    except:
        return jsonify({'success': False})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
