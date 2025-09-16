# Post-Mortem Process Demo

A comprehensive demonstration of effective post-mortem processes for learning from system failures.

## Features

- **Incident Management**: Create, track, and manage system incidents
- **Post-Mortem Creation**: Build comprehensive post-mortems with timeline analysis
- **Action Item Tracking**: Manage follow-up actions with assignees and due dates
- **Learning Analytics**: Visualize trends and insights from incident data
- **Blameless Culture**: Focus on system improvements rather than blame

## Quick Start

1. **Start the Demo**:
   ```bash
   ./demo.sh
   ```

2. **Access the Application**:
   - Frontend: http://localhost:3000
   - Backend API: http://localhost:8000/api/health

3. **Try the Demo Scenarios**:
   - Create a new incident
   - Build a post-mortem with root cause analysis
   - Add action items with due dates
   - Explore analytics dashboard

4. **Stop the Demo**:
   ```bash
   ./cleanup.sh
   ```

## Architecture

### Backend (Node.js/Express)
- REST API for incident and post-mortem management
- SQLite database for data persistence
- Real-time updates via WebSocket

### Frontend (React)
- Modern React application with routing
- Responsive dashboard design
- Real-time incident tracking
- Interactive post-mortem builder

### Database Schema
- `incidents`: System incidents and outages
- `postmortems`: Post-mortem documents and analysis
- `action_items`: Follow-up actions and assignments
- `timeline_events`: Incident timeline tracking

## Learning Objectives

- Understand blameless post-mortem culture
- Learn effective incident documentation
- Practice root cause analysis techniques
- Experience action item tracking workflows
- Observe learning pattern recognition

## Production Considerations

This demo showcases production-ready patterns:
- Comprehensive error handling
- Security headers and rate limiting
- Database persistence and recovery
- Real-time collaboration features
- Analytics and reporting capabilities

## Testing

Run automated tests:
```bash
./demo.sh
# Tests run automatically during startup
```

## Troubleshooting

- **Port conflicts**: Stop services using ports 3000 or 8000
- **Docker issues**: Ensure Docker daemon is running
- **Slow startup**: Services may take 30-60 seconds to initialize
- **Database issues**: Delete and restart to reset database

For more help, check the logs:
```bash
./demo.sh logs
```
