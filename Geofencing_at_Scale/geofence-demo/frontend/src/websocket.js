// WebSocket singleton to prevent duplicate connections in React StrictMode
class WebSocketManager {
  constructor() {
    this.ws = null;
    this.listeners = new Set();
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    this.reconnectTimeout = null;
    this.isConnecting = false;
  }

  connect() {
    // Don't create new connection if one already exists and is open/connecting
    if (this.ws && 
        (this.ws.readyState === WebSocket.OPEN || 
         this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    // Prevent multiple simultaneous connection attempts
    if (this.isConnecting) {
      return;
    }

    this.isConnecting = true;

    try {
      // Close existing connection if any
      if (this.ws && this.ws.readyState !== WebSocket.CLOSED) {
        this.ws.close();
      }

      this.ws = new WebSocket('ws://localhost:3000');

      this.ws.onopen = () => {
        this.isConnecting = false;
        this.reconnectAttempts = 0;
        this.notifyListeners({ type: 'open' });
        console.log('WebSocket connected');
      };

      this.ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          this.notifyListeners({ type: 'message', data });
        } catch (err) {
          console.error('Failed to parse WebSocket message:', err);
        }
      };

      this.ws.onerror = (error) => {
        this.isConnecting = false;
        console.error('WebSocket error:', error);
        this.notifyListeners({ type: 'error', error });
      };

      this.ws.onclose = (event) => {
        this.isConnecting = false;
        this.notifyListeners({ type: 'close', code: event.code, reason: event.reason });
        
        // Don't log normal closures (code 1000) as errors
        if (event.code === 1000) {
          console.log('WebSocket closed normally');
          return;
        }
        
        console.log('WebSocket disconnected', event.code, event.reason);
        
        // Reconnect if not a normal closure and we haven't exceeded max attempts
        if (event.code !== 1000 && this.reconnectAttempts < this.maxReconnectAttempts) {
          this.reconnectAttempts++;
          const delay = Math.min(3000 * this.reconnectAttempts, 10000);
          console.log(`Attempting to reconnect (${this.reconnectAttempts}/${this.maxReconnectAttempts}) in ${delay/1000} seconds...`);
          this.reconnectTimeout = setTimeout(() => {
            this.connect();
          }, delay);
        } else if (this.reconnectAttempts >= this.maxReconnectAttempts) {
          console.error('Max reconnection attempts reached. Please refresh the page.');
        }
      };
    } catch (error) {
      this.isConnecting = false;
      console.error('Failed to create WebSocket:', error);
      this.notifyListeners({ type: 'error', error });
      
      // Retry connection after delay if we haven't exceeded max attempts
      if (this.reconnectAttempts < this.maxReconnectAttempts) {
        this.reconnectAttempts++;
        const delay = Math.min(3000 * this.reconnectAttempts, 10000);
        this.reconnectTimeout = setTimeout(() => {
          this.connect();
        }, delay);
      }
    }
  }

  disconnect() {
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }
    
    if (this.ws) {
      if (this.ws.readyState !== WebSocket.CLOSED &&
          this.ws.readyState !== WebSocket.CLOSING) {
        this.ws.close(1000, 'Disconnecting');
      }
      this.ws = null;
    }
    
    this.isConnecting = false;
  }

  addListener(callback) {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  notifyListeners(event) {
    this.listeners.forEach(callback => {
      try {
        callback(event);
      } catch (err) {
        console.error('Error in WebSocket listener:', err);
      }
    });
  }

  isConnected() {
    return this.ws && this.ws.readyState === WebSocket.OPEN;
  }
}

// Export singleton instance
export const wsManager = new WebSocketManager();

