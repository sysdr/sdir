import React, { useState, useEffect, useRef } from 'react';
import io from 'socket.io-client';
import styled from 'styled-components';
import { Video, VideoOff, Mic, MicOff, Phone, PhoneOff, Users, MessageCircle, Settings } from 'lucide-react';

const Container = styled.div`
  display: flex;
  width: 100vw;
  height: 100vh;
  min-height: 100vh;
  overflow: hidden;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
`;

const MainArea = styled.div`
  flex: 1;
  display: flex;
  flex-direction: column;
  padding: 20px;
  min-width: 0;
  overflow: hidden;
`;

const Header = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(10px);
  padding: 15px 25px;
  border-radius: 15px;
  margin-bottom: 20px;
  color: white;
`;

const VideoGrid = styled.div`
  flex: 1;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 15px;
  margin-bottom: 20px;
  min-height: 0;
  overflow-y: auto;
`;

const VideoContainer = styled.div`
  position: relative;
  background: rgba(0, 0, 0, 0.3);
  border-radius: 15px;
  overflow: hidden;
  aspect-ratio: 16/9;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
`;

const VideoElement = styled.video`
  width: 100%;
  height: 100%;
  object-fit: cover;
`;

const VideoLabel = styled.div`
  position: absolute;
  bottom: 10px;
  left: 10px;
  background: rgba(0, 0, 0, 0.6);
  color: white;
  padding: 5px 10px;
  border-radius: 8px;
  font-size: 12px;
`;

const Controls = styled.div`
  display: flex;
  justify-content: center;
  gap: 15px;
  background: rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(10px);
  padding: 20px;
  border-radius: 15px;
`;

const ControlButton = styled.button`
  display: flex;
  align-items: center;
  justify-content: center;
  width: 50px;
  height: 50px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-radius: 50%;
  background: ${props => props.active ? '#4CAF50' : props.danger ? '#f44336' : 'rgba(255, 255, 255, 0.8)'};
  color: ${props => props.active || props.danger ? 'white' : '#667eea'};
  cursor: pointer;
  transition: all 0.3s ease;
  backdrop-filter: blur(10px);
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.2);

  &:hover {
    transform: scale(1.1);
    background: ${props => props.active ? '#45a049' : props.danger ? '#e53935' : 'rgba(255, 255, 255, 0.95)'};
    border-color: rgba(255, 255, 255, 0.5);
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.3);
  }

  &:active {
    transform: scale(1.05);
  }
`;

const Sidebar = styled.div`
  width: 350px;
  min-width: 350px;
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(10px);
  display: flex;
  flex-direction: column;
  border-left: 1px solid rgba(255, 255, 255, 0.2);
  overflow: hidden;
`;

const SidebarTab = styled.div`
  display: flex;
  border-bottom: 1px solid rgba(0, 0, 0, 0.1);
`;

const TabButton = styled.button`
  flex: 1;
  padding: 15px;
  border: none;
  background: ${props => props.active ? '#2196F3' : 'rgba(0, 0, 0, 0.05)'};
  color: ${props => props.active ? 'white' : '#333'};
  cursor: pointer;
  transition: all 0.3s ease;
  font-weight: ${props => props.active ? '600' : '400'};
  border-bottom: 2px solid ${props => props.active ? '#2196F3' : 'transparent'};

  &:hover {
    background: ${props => props.active ? '#1976D2' : 'rgba(33, 150, 243, 0.15)'};
    color: ${props => props.active ? 'white' : '#2196F3'};
  }
`;

const TabContent = styled.div`
  flex: 1;
  padding: 20px;
  overflow-y: auto;
`;

const ParticipantList = styled.div`
  display: flex;
  flex-direction: column;
  gap: 10px;
`;

const Participant = styled.div`
  display: flex;
  align-items: center;
  padding: 10px;
  background: rgba(33, 150, 243, 0.1);
  border-radius: 8px;
  gap: 10px;
`;

const ChatArea = styled.div`
  display: flex;
  flex-direction: column;
  height: 100%;
`;

const MessageList = styled.div`
  flex: 1;
  overflow-y: auto;
  margin-bottom: 15px;
`;

const Message = styled.div`
  margin-bottom: 10px;
  padding: 8px 12px;
  background: rgba(33, 150, 243, 0.1);
  border-radius: 8px;
  font-size: 14px;
`;

const ChatInput = styled.div`
  display: flex;
  gap: 10px;
`;

const Input = styled.input`
  flex: 1;
  padding: 10px;
  border: 1px solid #ddd;
  border-radius: 8px;
  outline: none;

  &:focus {
    border-color: #2196F3;
  }
`;

const JoinModal = styled.div`
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.8);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
`;

const Modal = styled.div`
  background: white;
  padding: 30px;
  border-radius: 15px;
  width: 400px;
  text-align: center;
`;

const STUN_SERVERS = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' }
];

function App() {
  const [socket, setSocket] = useState(null);
  const [joined, setJoined] = useState(false);
  const [roomId, setRoomId] = useState('');
  const [userName, setUserName] = useState('');
  const [localStream, setLocalStream] = useState(null);
  const [peers, setPeers] = useState(new Map());
  const [participants, setParticipants] = useState([]);
  const [messages, setMessages] = useState([]);
  const [currentMessage, setCurrentMessage] = useState('');
  const [activeTab, setActiveTab] = useState('participants');
  const [isVideoOn, setIsVideoOn] = useState(true);
  const [isAudioOn, setIsAudioOn] = useState(true);
  const [connectionStats, setConnectionStats] = useState({});

  const localVideoRef = useRef();
  const remoteVideoRefs = useRef(new Map());

  useEffect(() => {
    const newSocket = io('http://localhost:3001');
    setSocket(newSocket);

    newSocket.on('user-joined', handleUserJoined);
    newSocket.on('existing-users', handleExistingUsers);
    newSocket.on('user-left', handleUserLeft);
    newSocket.on('webrtc-offer', handleWebRTCOffer);
    newSocket.on('webrtc-answer', handleWebRTCAnswer);
    newSocket.on('webrtc-ice-candidate', handleWebRTCIceCandidate);
    newSocket.on('chat-message', handleChatMessage);

    return () => {
      newSocket.disconnect();
      if (localStream) {
        localStream.getTracks().forEach(track => track.stop());
      }
    };
  }, []);

  const joinRoom = async () => {
    if (!roomId || !userName) return;

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: true,
        audio: true
      });

      setLocalStream(stream);
      if (localVideoRef.current) {
        localVideoRef.current.srcObject = stream;
      }

      socket.emit('join-room', { roomId, userName });
      setJoined(true);
    } catch (error) {
      console.error('Error accessing media devices:', error);
      alert('Could not access camera/microphone. Please check permissions.');
    }
  };

  const createPeerConnection = (userId) => {
    const pc = new RTCPeerConnection({ iceServers: STUN_SERVERS });

    pc.onicecandidate = (event) => {
      if (event.candidate) {
        socket.emit('webrtc-ice-candidate', {
          targetUserId: userId,
          candidate: event.candidate
        });
      }
    };

    pc.ontrack = (event) => {
      const remoteVideoRef = remoteVideoRefs.current.get(userId);
      if (remoteVideoRef) {
        remoteVideoRef.srcObject = event.streams[0];
      }
    };

    // Add connection state monitoring
    pc.onconnectionstatechange = () => {
      setConnectionStats(prev => ({
        ...prev,
        [userId]: {
          state: pc.connectionState,
          iceState: pc.iceConnectionState
        }
      }));
    };

    if (localStream) {
      localStream.getTracks().forEach(track => {
        pc.addTrack(track, localStream);
      });
    }

    return pc;
  };

  const handleUserJoined = async (userInfo) => {
    console.log('User joined:', userInfo);
    setParticipants(prev => [...prev, userInfo]);

    const pc = createPeerConnection(userInfo.id);
    setPeers(prev => new Map(prev).set(userInfo.id, pc));

    // Create offer
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    socket.emit('webrtc-offer', {
      targetUserId: userInfo.id,
      offer: offer
    });
  };

  const handleExistingUsers = (users) => {
    setParticipants(users);
  };

  const handleUserLeft = ({ userId }) => {
    setParticipants(prev => prev.filter(p => p.id !== userId));
    const peer = peers.get(userId);
    if (peer) {
      peer.close();
      setPeers(prev => {
        const newPeers = new Map(prev);
        newPeers.delete(userId);
        return newPeers;
      });
    }
    remoteVideoRefs.current.delete(userId);
  };

  const handleWebRTCOffer = async ({ offer, fromUserId }) => {
    const pc = createPeerConnection(fromUserId);
    setPeers(prev => new Map(prev).set(fromUserId, pc));

    await pc.setRemoteDescription(offer);
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    socket.emit('webrtc-answer', {
      targetUserId: fromUserId,
      answer: answer
    });
  };

  const handleWebRTCAnswer = async ({ answer, fromUserId }) => {
    const pc = peers.get(fromUserId);
    if (pc) {
      await pc.setRemoteDescription(answer);
    }
  };

  const handleWebRTCIceCandidate = async ({ candidate, fromUserId }) => {
    const pc = peers.get(fromUserId);
    if (pc) {
      await pc.addIceCandidate(candidate);
    }
  };

  const handleChatMessage = (messageData) => {
    setMessages(prev => [...prev, messageData]);
  };

  const sendMessage = () => {
    if (currentMessage.trim()) {
      socket.emit('chat-message', { message: currentMessage });
      setCurrentMessage('');
    }
  };

  const toggleVideo = () => {
    if (localStream) {
      const videoTrack = localStream.getVideoTracks()[0];
      if (videoTrack) {
        videoTrack.enabled = !videoTrack.enabled;
        setIsVideoOn(videoTrack.enabled);
      }
    }
  };

  const toggleAudio = () => {
    if (localStream) {
      const audioTrack = localStream.getAudioTracks()[0];
      if (audioTrack) {
        audioTrack.enabled = !audioTrack.enabled;
        setIsAudioOn(audioTrack.enabled);
      }
    }
  };

  const leaveRoom = () => {
    if (localStream) {
      localStream.getTracks().forEach(track => track.stop());
    }
    peers.forEach(peer => peer.close());
    setPeers(new Map());
    setParticipants([]);
    setJoined(false);
    socket.disconnect();
    window.location.reload();
  };

  if (!joined) {
    return (
      <JoinModal>
        <Modal>
          <h2 style={{ color: '#333', marginBottom: '20px' }}>Join Video Conference</h2>
          <Input
            type="text"
            placeholder="Enter your name"
            value={userName}
            onChange={(e) => setUserName(e.target.value)}
            style={{ marginBottom: '15px' }}
          />
          <Input
            type="text"
            placeholder="Enter room ID"
            value={roomId}
            onChange={(e) => setRoomId(e.target.value)}
            style={{ marginBottom: '20px' }}
          />
          <ControlButton 
            onClick={joinRoom}
            style={{ 
              width: 'auto', 
              padding: '12px 30px', 
              borderRadius: '8px',
              background: '#2196F3',
              color: 'white',
              border: '2px solid #1976D2',
              fontWeight: '600'
            }}
          >
            Join Room
          </ControlButton>
        </Modal>
      </JoinModal>
    );
  }

  return (
    <Container>
      <MainArea>
        <Header>
          <h2>Room: {roomId}</h2>
          <div style={{ display: 'flex', alignItems: 'center', gap: '15px' }}>
            <span><Users size={16} /> {participants.length + 1} participants</span>
            <span>🟢 Connected</span>
          </div>
        </Header>

        <VideoGrid>
          <VideoContainer>
            <VideoElement
              ref={localVideoRef}
              autoPlay
              muted
              playsInline
            />
            <VideoLabel>You ({userName})</VideoLabel>
          </VideoContainer>

          {participants.map(participant => (
            <VideoContainer key={participant.id}>
              <VideoElement
                ref={ref => {
                  if (ref) remoteVideoRefs.current.set(participant.id, ref);
                }}
                autoPlay
                playsInline
              />
              <VideoLabel>
                {participant.userName}
                {connectionStats[participant.id] && (
                  <span style={{ marginLeft: '5px', fontSize: '10px' }}>
                    {connectionStats[participant.id].state === 'connected' ? '🟢' : '🟡'}
                  </span>
                )}
              </VideoLabel>
            </VideoContainer>
          ))}
        </VideoGrid>

        <Controls>
          <ControlButton active={isVideoOn} onClick={toggleVideo}>
            {isVideoOn ? <Video size={20} /> : <VideoOff size={20} />}
          </ControlButton>
          <ControlButton active={isAudioOn} onClick={toggleAudio}>
            {isAudioOn ? <Mic size={20} /> : <MicOff size={20} />}
          </ControlButton>
          <ControlButton danger onClick={leaveRoom}>
            <PhoneOff size={20} />
          </ControlButton>
        </Controls>
      </MainArea>

      <Sidebar>
        <SidebarTab>
          <TabButton 
            active={activeTab === 'participants'} 
            onClick={() => setActiveTab('participants')}
          >
            <Users size={16} style={{ marginRight: '5px' }} />
            Participants
          </TabButton>
          <TabButton 
            active={activeTab === 'chat'} 
            onClick={() => setActiveTab('chat')}
          >
            <MessageCircle size={16} style={{ marginRight: '5px' }} />
            Chat
          </TabButton>
        </SidebarTab>

        <TabContent>
          {activeTab === 'participants' && (
            <ParticipantList>
              <Participant>
                <div style={{ 
                  width: '10px', 
                  height: '10px', 
                  borderRadius: '50%', 
                  background: '#4CAF50' 
                }} />
                <span>{userName} (You)</span>
              </Participant>
              {participants.map(participant => (
                <Participant key={participant.id}>
                  <div style={{ 
                    width: '10px', 
                    height: '10px', 
                    borderRadius: '50%', 
                    background: connectionStats[participant.id]?.state === 'connected' ? '#4CAF50' : '#FF9800'
                  }} />
                  <span>{participant.userName}</span>
                </Participant>
              ))}
            </ParticipantList>
          )}

          {activeTab === 'chat' && (
            <ChatArea>
              <MessageList>
                {messages.map((msg, index) => (
                  <Message key={index}>
                    <strong>{msg.userName}:</strong> {msg.message}
                    <div style={{ fontSize: '11px', color: '#666', marginTop: '3px' }}>
                      {new Date(msg.timestamp).toLocaleTimeString()}
                    </div>
                  </Message>
                ))}
              </MessageList>
              <ChatInput>
                <Input
                  type="text"
                  placeholder="Type a message..."
                  value={currentMessage}
                  onChange={(e) => setCurrentMessage(e.target.value)}
                  onKeyPress={(e) => e.key === 'Enter' && sendMessage()}
                />
                <ControlButton 
                  onClick={sendMessage}
                  style={{ 
                    width: 'auto', 
                    padding: '10px 20px', 
                    borderRadius: '8px',
                    background: '#2196F3',
                    color: 'white',
                    border: '2px solid #1976D2',
                    fontWeight: '600'
                  }}
                >
                  Send
                </ControlButton>
              </ChatInput>
            </ChatArea>
          )}
        </TabContent>
      </Sidebar>
    </Container>
  );
}

export default App;
