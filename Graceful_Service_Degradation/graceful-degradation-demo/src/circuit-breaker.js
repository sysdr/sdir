class CircuitBreaker {
    constructor(service, options = {}) {
        this.service = service;
        this.failureThreshold = options.failureThreshold || 5;
        this.recoveryTime = options.recoveryTime || 30000;
        this.timeout = options.timeout || 10000;
        
        this.state = 'CLOSED';
        this.failureCount = 0;
        this.nextAttempt = Date.now();
        this.successCount = 0;
    }

    async execute(operation) {
        if (this.state === 'OPEN') {
            if (Date.now() < this.nextAttempt) {
                throw new Error(`Circuit breaker OPEN for ${this.service}`);
            }
            this.state = 'HALF_OPEN';
        }

        try {
            const result = await Promise.race([
                operation(),
                this.timeoutPromise()
            ]);
            
            this.onSuccess();
            return result;
        } catch (error) {
            this.onFailure();
            throw error;
        }
    }

    onSuccess() {
        this.failureCount = 0;
        if (this.state === 'HALF_OPEN') {
            this.successCount++;
            if (this.successCount >= 3) {
                this.state = 'CLOSED';
                this.successCount = 0;
            }
        }
    }

    onFailure() {
        this.failureCount++;
        if (this.failureCount >= this.failureThreshold) {
            this.state = 'OPEN';
            this.nextAttempt = Date.now() + this.recoveryTime;
        }
    }

    timeoutPromise() {
        return new Promise((_, reject) => {
            setTimeout(() => reject(new Error('Timeout')), this.timeout);
        });
    }

    getState() {
        return {
            service: this.service,
            state: this.state,
            failureCount: this.failureCount,
            nextAttempt: this.nextAttempt
        };
    }
}

module.exports = CircuitBreaker;
