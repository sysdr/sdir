# Paxos Consensus Algorithm Docker Demo
# Provides convenient commands for Docker operations

.PHONY: help build run test clean logs shell

help: ## Show this help message
	@echo "Paxos Consensus Algorithm Docker Demo"
	@echo "====================================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $1, $2}'

build: ## Build Docker image
	@echo "🐳 Building Paxos Docker image..."
	docker build -t paxos-demo .

run: ## Run simulation in Docker container
	@echo "🚀 Running Paxos simulation in Docker..."
	docker run --rm -v $(PWD)/logs:/app/logs -v $(PWD)/state:/app/state paxos-demo

run-web: ## Start web interface in Docker
	@echo "🌐 Starting Paxos web interface..."
	docker run -d --name paxos-web -p 8080:8080 -v $(PWD)/logs:/app/logs:ro -v $(PWD)/state:/app/state:ro paxos-demo python3 start_web_server.py
	@echo "📊 Web interface available at http://localhost:8080"

compose-up: ## Start all services with docker-compose
	@echo "🎼 Starting Paxos services with Docker Compose..."
	docker-compose up -d

compose-down: ## Stop all services
	@echo "🛑 Stopping Paxos services..."
	docker-compose down

test: ## Run test suite in Docker
	@echo "🧪 Running Paxos tests in Docker..."
	docker run --rm -v $(PWD)/logs:/app/logs -v $(PWD)/state:/app/state -v $(PWD)/tests:/app/tests paxos-demo python3 tests/test_paxos.py

test-docker: ## Run Docker-specific integration tests
	@echo "🐳 Running Docker integration tests..."
	python3 test_docker.py

test-chaos: ## Run chaos engineering tests
	@echo "🔥 Starting chaos engineering test..."
	docker-compose --profile chaos --profile testing up --abort-on-container-exit

logs: ## View simulation logs
	@echo "📋 Paxos simulation logs:"
	@echo "========================"
	@tail -f logs/paxos_simulation.log

shell: ## Open shell in running container
	@echo "🐚 Opening shell in Paxos container..."
	docker exec -it paxos-web /bin/bash

clean: ## Clean up containers and images
	@echo "🧹 Cleaning up Docker resources..."
	docker-compose down -v --remove-orphans
	docker container prune -f
	docker image rm paxos-demo 2>/dev/null || true
	docker system prune -f

status: ## Show container status
	@echo "📊 Container Status:"
	@echo "==================="
	@docker ps --filter label=com.docker.compose.project=paxos_demo --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

benchmark: ## Run performance benchmarks
	@echo "⚡ Running Paxos performance benchmarks..."
	docker run --rm -v $(PWD)/logs:/app/logs paxos-demo python3 -c "
	from paxos_simulator import PaxosSimulation
	import time
	
	print('🔥 Paxos Performance Benchmark')
	print('=' * 40)
	
	# Test with different cluster sizes
	for n in [3, 5, 7, 9]:
		sim = PaxosSimulation(num_acceptors=n, num_proposers=1)
		start = time.time()
		success, value = sim.proposers[0].propose(f'test_n{n}')
		duration = time.time() - start
		print(f'Cluster size {n}: {duration:.3f}s (success: {success})')
	"
