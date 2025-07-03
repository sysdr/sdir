"""
Real-time comparison dashboard for stateless vs stateful services
"""
import dash
from dash import dcc, html, Input, Output
import dash_bootstrap_components as dbc
import plotly.graph_objs as go
import requests
import pandas as pd
from datetime import datetime, timedelta
import time
import threading
import json

# Initialize Dash app
app = dash.Dash(__name__, external_stylesheets=[dbc.themes.BOOTSTRAP])

# Global data storage
metrics_data = {
    'stateless': [],
    'stateful': []
}

def fetch_metrics():
    """Fetch metrics from both services"""
    while True:
        try:
            # Fetch stateless metrics
            try:
                response = requests.get('http://stateless-service:8000/metrics', timeout=5)
                if response.status_code == 200:
                    data = response.json()
                    data['timestamp'] = datetime.now()
                    metrics_data['stateless'].append(data)
                    
                    # Keep only last 50 data points
                    if len(metrics_data['stateless']) > 50:
                        metrics_data['stateless'] = metrics_data['stateless'][-50:]
            except:
                pass
            
            # Fetch stateful metrics
            try:
                response = requests.get('http://stateful-service:8001/metrics', timeout=5)
                if response.status_code == 200:
                    data = response.json()
                    data['timestamp'] = datetime.now()
                    metrics_data['stateful'].append(data)
                    
                    # Keep only last 50 data points
                    if len(metrics_data['stateful']) > 50:
                        metrics_data['stateful'] = metrics_data['stateful'][-50:]
            except:
                pass
                
        except Exception as e:
            print(f"Error fetching metrics: {e}")
        
        time.sleep(2)

# Start metrics collection in background
metrics_thread = threading.Thread(target=fetch_metrics, daemon=True)
metrics_thread.start()

# Layout
app.layout = dbc.Container([
    dbc.Row([
        dbc.Col([
            html.H1("Stateless vs Stateful Services Comparison", 
                   className="text-center mb-4 text-primary"),
            html.Hr()
        ])
    ]),
    
    dbc.Row([
        dbc.Col([
            dbc.Card([
                dbc.CardHeader("📊 Real-time Metrics Comparison"),
                dbc.CardBody([
                    dcc.Graph(id='metrics-comparison')
                ])
            ])
        ], width=12)
    ], className="mb-4"),
    
    dbc.Row([
        dbc.Col([
            dbc.Card([
                dbc.CardHeader("🔄 Active Sessions"),
                dbc.CardBody([
                    dcc.Graph(id='sessions-chart')
                ])
            ])
        ], width=6),
        dbc.Col([
            dbc.Card([
                dbc.CardHeader("💾 Memory Usage"),
                dbc.CardBody([
                    dcc.Graph(id='memory-chart')
                ])
            ])
        ], width=6)
    ], className="mb-4"),
    
    dbc.Row([
        dbc.Col([
            dbc.Card([
                dbc.CardHeader("📈 Request Count"),
                dbc.CardBody([
                    dcc.Graph(id='requests-chart')
                ])
            ])
        ], width=6),
        dbc.Col([
            dbc.Card([
                dbc.CardHeader("🎯 Key Insights"),
                dbc.CardBody([
                    html.Div(id='insights-panel')
                ])
            ])
        ], width=6)
    ]),
    
    # Auto-refresh interval
    dcc.Interval(id='interval-component', interval=3000, n_intervals=0)
], fluid=True)

@app.callback(
    [Output('metrics-comparison', 'figure'),
     Output('sessions-chart', 'figure'),
     Output('memory-chart', 'figure'),
     Output('requests-chart', 'figure'),
     Output('insights-panel', 'children')],
    [Input('interval-component', 'n_intervals')]
)
def update_dashboard(n):
    # Create figures
    fig_comparison = create_comparison_chart()
    fig_sessions = create_sessions_chart()
    fig_memory = create_memory_chart()
    fig_requests = create_requests_chart()
    insights = create_insights_panel()
    
    return fig_comparison, fig_sessions, fig_memory, fig_requests, insights

def create_comparison_chart():
    """Create the main comparison chart"""
    fig = go.Figure()
    
    # Add CPU usage for both services
    if metrics_data['stateless']:
        timestamps = [d['timestamp'] for d in metrics_data['stateless']]
        cpu_values = [d['cpu_usage'] for d in metrics_data['stateless']]
        fig.add_trace(go.Scatter(
            x=timestamps, y=cpu_values,
            mode='lines+markers',
            name='Stateless CPU %',
            line=dict(color='#28a745')
        ))
    
    if metrics_data['stateful']:
        timestamps = [d['timestamp'] for d in metrics_data['stateful']]
        cpu_values = [d['cpu_usage'] for d in metrics_data['stateful']]
        fig.add_trace(go.Scatter(
            x=timestamps, y=cpu_values,
            mode='lines+markers',
            name='Stateful CPU %',
            line=dict(color='#ffc107')
        ))
    
    fig.update_layout(
        title="CPU Usage Comparison",
        xaxis_title="Time",
        yaxis_title="CPU Usage (%)",
        hovermode='x'
    )
    
    return fig

def create_sessions_chart():
    """Create sessions comparison chart"""
    fig = go.Figure()
    
    if metrics_data['stateless']:
        timestamps = [d['timestamp'] for d in metrics_data['stateless']]
        sessions = [d['active_sessions'] for d in metrics_data['stateless']]
        fig.add_trace(go.Scatter(
            x=timestamps, y=sessions,
            mode='lines+markers',
            name='Stateless',
            line=dict(color='#28a745')
        ))
    
    if metrics_data['stateful']:
        timestamps = [d['timestamp'] for d in metrics_data['stateful']]
        sessions = [d['active_sessions'] for d in metrics_data['stateful']]
        fig.add_trace(go.Scatter(
            x=timestamps, y=sessions,
            mode='lines+markers',
            name='Stateful',
            line=dict(color='#ffc107')
        ))
    
    fig.update_layout(
        title="Active Sessions",
        xaxis_title="Time",
        yaxis_title="Session Count"
    )
    
    return fig

def create_memory_chart():
    """Create memory usage chart"""
    fig = go.Figure()
    
    if metrics_data['stateless']:
        timestamps = [d['timestamp'] for d in metrics_data['stateless']]
        memory = [d['memory_usage'] for d in metrics_data['stateless']]
        fig.add_trace(go.Scatter(
            x=timestamps, y=memory,
            mode='lines+markers',
            name='Stateless',
            line=dict(color='#28a745')
        ))
    
    if metrics_data['stateful']:
        timestamps = [d['timestamp'] for d in metrics_data['stateful']]
        memory = [d['memory_usage'] for d in metrics_data['stateful']]
        fig.add_trace(go.Scatter(
            x=timestamps, y=memory,
            mode='lines+markers',
            name='Stateful',
            line=dict(color='#ffc107')
        ))
    
    fig.update_layout(
        title="Memory Usage (%)",
        xaxis_title="Time",
        yaxis_title="Memory Usage (%)"
    )
    
    return fig

def create_requests_chart():
    """Create request count chart"""
    fig = go.Figure()
    
    if metrics_data['stateless']:
        timestamps = [d['timestamp'] for d in metrics_data['stateless']]
        requests = [d['request_count'] for d in metrics_data['stateless']]
        fig.add_trace(go.Scatter(
            x=timestamps, y=requests,
            mode='lines+markers',
            name='Stateless',
            line=dict(color='#28a745')
        ))
    
    if metrics_data['stateful']:
        timestamps = [d['timestamp'] for d in metrics_data['stateful']]
        requests = [d['request_count'] for d in metrics_data['stateful']]
        fig.add_trace(go.Scatter(
            x=timestamps, y=requests,
            mode='lines+markers',
            name='Stateful',
            line=dict(color='#ffc107')
        ))
    
    fig.update_layout(
        title="Total Requests Processed",
        xaxis_title="Time",
        yaxis_title="Request Count"
    )
    
    return fig

def create_insights_panel():
    """Create insights panel"""
    stateless_sessions = metrics_data['stateless'][-1]['active_sessions'] if metrics_data['stateless'] else 0
    stateful_sessions = metrics_data['stateful'][-1]['active_sessions'] if metrics_data['stateful'] else 0
    
    insights = [
        dbc.Alert([
            html.H6("🔄 Session Management", className="alert-heading"),
            html.P(f"Stateless: {stateless_sessions} sessions (JWT-based)"),
            html.P(f"Stateful: {stateful_sessions} sessions (Server memory)")
        ], color="info"),
        
        dbc.Alert([
            html.H6("📈 Scaling Behavior", className="alert-heading"),
            html.P("Stateless: Linear scaling, no session affinity"),
            html.P("Stateful: Session affinity required, memory bound")
        ], color="warning"),
        
        dbc.Alert([
            html.H6("💡 Key Takeaway", className="alert-heading"),
            html.P("Stateful services consume more memory per user but offer faster state access. Stateless services scale horizontally with ease.")
        ], color="success")
    ]
    
    return insights

if __name__ == '__main__':
    app.run_server(host='0.0.0.0', port=8080, debug=False)
