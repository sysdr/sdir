import React, { useState, useEffect, useRef } from 'react';
import './App.css';

const CHANNEL_ID = 'demo-channel';
const API_URL = 'http://localhost:3001';
const WS_URL = 'ws://localhost:3001';

function App() {
  const [username, setUsername] = useState('');
  const [userId, setUserId] = useState('');
  const [isConnected, setIsConnected] = useState(false);
  const [messages, setMessages] = useState([]);
  const [newMessage, setNewMessage] = useState('');
  const [presence, setPresence] = useState([]);
  const [stats, setStats] = useState({});
  const [readReceipts, setReadReceipts] = useState({});
  const wsRef = useRef(null);
  const messagesEndRef = useRef(null);

  useEffect(() => {
    if (isConnected) {
      fetchMessages();
      fetchPresence();
      fetchStats();
      
      const interval = setInterval(() => {
        fetchPresence();
        fetchStats();
      }, 5000);
      
      const heartbeatInterval = setInterval(() => {
        if (wsRef.current?.readyState === 1) {
          wsRef.current.send(JSON.stringify({ type: 'heartbeat' }));
        }
      }, 30000);
      
      return () => {
        clearInterval(interval);
        clearInterval(heartbeatInterval);
      };
    }
  }, [isConnected]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const fetchMessages = async () => {
    try {
      const res = await fetch(`${API_URL}/api/messages/${CHANNEL_ID}`);
      const data = await res.json();
      setMessages(data);
    } catch (error) {
      console.error('Error fetching messages:', error);
    }
  };

  const fetchPresence = async () => {
    try {
      const res = await fetch(`${API_URL}/api/presence`);
      const data = await res.json();
      setPresence(data);
    } catch (error) {
      console.error('Error fetching presence:', error);
    }
  };

  const fetchStats = async () => {
    try {
      const res = await fetch(`${API_URL}/api/stats`);
      const data = await res.json();
      setStats(data);
    } catch (error) {
      console.error('Error fetching stats:', error);
    }
  };

  const connect = () => {
    if (!username.trim()) return;
    
    const newUserId = `user_${Math.random().toString(36).substr(2, 9)}`;
    setUserId(newUserId);
    
    const ws = new WebSocket(WS_URL);
    
    ws.onopen = () => {
      console.log('WebSocket connected');
      ws.send(JSON.stringify({
        type: 'join',
        userId: newUserId,
        username: username.trim()
      }));
      setIsConnected(true);
    };
    
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      
      switch (data.type) {
        case 'message':
          setMessages(prev => [...prev, data]);
          break;
          
        case 'read_receipt':
          setReadReceipts(prev => ({
            ...prev,
            [data.messageId]: data.readCount
          }));
          break;
          
        case 'presence':
          fetchPresence();
          break;
          
        case 'heartbeat_ack':
          console.log('Heartbeat acknowledged');
          break;
      }
    };
    
    ws.onerror = (error) => {
      console.error('WebSocket error:', error);
    };
    
    ws.onclose = () => {
      console.log('WebSocket disconnected');
      setIsConnected(false);
    };
    
    wsRef.current = ws;
  };

  const sendMessage = () => {
    if (!newMessage.trim() || !wsRef.current) return;
    
    wsRef.current.send(JSON.stringify({
      type: 'message',
      channelId: CHANNEL_ID,
      content: newMessage.trim()
    }));
    
    setNewMessage('');
  };

  const markAsRead = (messageId) => {
    if (!wsRef.current) return;
    
    wsRef.current.send(JSON.stringify({
      type: 'read',
      channelId: CHANNEL_ID,
      messageId
    }));
  };

  if (!isConnected) {
    return (
      <div className="login-container">
        <div className="login-card">
          <h1>💬 Chat System Demo</h1>
          <p>Demonstrating message storage, read receipts & presence</p>
          <input
            type="text"
            placeholder="Enter your username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            onKeyPress={(e) => e.key === 'Enter' && connect()}
            autoFocus
          />
          <button onClick={connect} disabled={!username.trim()}>
            Join Chat
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="app">
      <header>
        <h1>💬 Chat System Demo</h1>
        <div className="header-info">
          <span>Logged in as: <strong>{username}</strong></span>
        </div>
      </header>

      <div className="main-container">
        <div className="sidebar">
          <div className="panel">
            <h3>📊 System Stats</h3>
            <div className="stat">
              <span className="label">Total Messages:</span>
              <span className="value">{stats.totalMessages || 0}</span>
            </div>
            <div className="stat">
              <span className="label">Read Receipts:</span>
              <span className="value">{stats.totalReadReceipts || 0}</span>
            </div>
            <div className="stat">
              <span className="label">Online Users:</span>
              <span className="value">{stats.onlineUsers || 0}</span>
            </div>
            <div className="stat">
              <span className="label">WS Connections:</span>
              <span className="value">{stats.connectedClients || 0}</span>
            </div>
          </div>

          <div className="panel">
            <h3>👥 Presence</h3>
            <div className="presence-list">
              {presence.map((user) => (
                <div key={user.userId} className="presence-item">
                  <div className={`status-dot ${user.status}`}></div>
                  <div className="presence-info">
                    <div className="presence-username">{user.username}</div>
                    <div className="presence-status">
                      {user.status === 'online' ? 'Online' : `Last seen: ${new Date(user.lastSeen).toLocaleTimeString()}`}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="chat-container">
          <div className="messages">
            {messages.map((msg) => (
              <div
                key={msg.id}
                className={`message ${msg.userId === userId ? 'own' : ''}`}
              >
                <div className="message-header">
                  <span className="message-username">{msg.username}</span>
                  <span className="message-time">
                    {new Date(msg.timestamp).toLocaleTimeString()}
                  </span>
                </div>
                <div className="message-content">{msg.content}</div>
                <div className="message-footer">
                  {msg.persistLatency && (
                    <span className="persist-latency">
                      ✓ Persisted in {msg.persistLatency}ms
                    </span>
                  )}
                  {readReceipts[msg.id] && (
                    <span className="read-count">
                      👁️ {readReceipts[msg.id]} read{readReceipts[msg.id] > 1 ? 's' : ''}
                    </span>
                  )}
                  {msg.userId !== userId && (
                    <button
                      className="mark-read-btn"
                      onClick={() => markAsRead(msg.id)}
                    >
                      Mark as read
                    </button>
                  )}
                </div>
              </div>
            ))}
            <div ref={messagesEndRef} />
          </div>

          <div className="input-container">
            <input
              type="text"
              placeholder="Type a message..."
              value={newMessage}
              onChange={(e) => setNewMessage(e.target.value)}
              onKeyPress={(e) => e.key === 'Enter' && sendMessage()}
            />
            <button onClick={sendMessage} disabled={!newMessage.trim()}>
              Send
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
