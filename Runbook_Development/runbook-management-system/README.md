# Runbook Management System Demo

A comprehensive demonstration of standardized operational procedures with real-time execution tracking.

## Features

- **Interactive Runbook Creator** with template-based generation
- **Real-time Execution Tracking** with step-by-step progress monitoring
- **Analytics Dashboard** showing usage patterns and performance metrics
- **Template System** for standardizing runbook creation
- **Execution History** with detailed logging and status tracking

## Quick Start

```bash
# Start the complete system
./demo.sh

# Access the application
open http://localhost:3000
```

## Architecture

- **Backend**: Node.js with Express and SQLite
- **Frontend**: React with Tailwind CSS
- **Database**: SQLite with comprehensive schema
- **Containerization**: Docker with optimized multi-stage builds

## API Endpoints

- `GET /api/runbooks` - List all runbooks
- `GET /api/runbooks/:id` - Get runbook details
- `POST /api/runbooks` - Create new runbook
- `POST /api/executions` - Start runbook execution
- `PUT /api/executions/:id` - Update execution status
- `GET /api/analytics` - Get usage analytics

## Demo Scenarios

1. **Browse Existing Runbooks** - View pre-loaded operational procedures
2. **Execute a Runbook** - Step through procedures with real-time tracking
3. **Create Custom Runbook** - Build new procedures with the interactive creator
4. **View Analytics** - Analyze runbook usage and effectiveness patterns

## Learning Objectives

- Understand runbook standardization principles
- Experience real-time execution tracking
- Learn operational procedure best practices
- Practice incident response automation patterns

## Clean Up

```bash
./cleanup.sh
```
