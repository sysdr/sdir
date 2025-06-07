class GossipNode:
    """Implementation of a SWIM-based gossip protocol node"""
    
    def __init__(self, node_id: str, host: str, port: int, web_port: int):
        self.node_id = node_id
        self.host = host
        self.port = port
        self.web_port = web_port
        
        # Node state
        self.is_running = False
        self.members: Dict[str, NodeState] = {}
        self.gossip_queue: List[GossipMessage] = []
        self.local_data: Dict[str, any] = {}
        self.vector_clock: Dict[str, int] = defaultdict(int)
        
        # Gossip parameters
        self.gossip_interval = 1.0  # Reduced from 2.0 to 1.0 for faster propagation
        self.fanout = 2  # Reduced from 3 to 2 to avoid network congestion
        self.max_excitement = 8  # Reduced from 10 to 8
        self.excitement_threshold = 1  # Reduced from 2 to 1 for longer propagation
        
        # SWIM parameters
        self.ping_timeout = 1.0
        self.ping_interval = 5.0
        self.suspect_timeout = 10.0
        
        # Statistics
        self.stats = {
            'messages_sent': 0,
            'messages_received': 0,
            'gossip_rounds': 0,
            'failed_pings': 0
        }
        
        # Flask app for web interface
        self.app = Flask(__name__)
        self.app.config['SECRET_KEY'] = 'gossip-demo'
        self.socketio = SocketIO(self.app, cors_allowed_origins="*")
        
        self.setup_routes()
        self.logger = logging.getLogger(f"GossipNode-{node_id}")

    def start(self):
        """Start the gossip node"""
        self.is_running = True
        self.logger.info(f"Starting gossip node {self.node_id} on {self.host}:{self.web_port}")
        
        # Start background threads
        threading.Thread(target=self.gossip_loop, daemon=True).start()
        threading.Thread(target=self.ping_loop, daemon=True).start()
        threading.Thread(target=self.web_server, daemon=True).start()
        
        # Add self to members
        self.members[self.node_id] = NodeState(
            id=self.node_id,
            host=self.host,
            port=self.web_port,
            last_seen=time.time()
        )
        
        # Join cluster with other nodes
        seed_nodes = [
            ("localhost", 9001),
            ("localhost", 9002),
            ("localhost", 9003),
            ("localhost", 9004),
            ("localhost", 9005)
        ]
        self.join_cluster(seed_nodes)

    def handle_gossip_message(self, message: GossipMessage):
        """Handle incoming gossip message"""
        self.stats['messages_received'] += 1
        
        # Update vector clock
        if message.sender_id in self.vector_clock:
            self.vector_clock[message.sender_id] = max(
                self.vector_clock[message.sender_id],
                message.propagation_count
            )
        
        # Process the message data
        if message.data.get('operation') == 'update':
            key = message.data.get('key')
            value = message.data.get('value')
            
            # Always update local data and propagate
            self.local_data[key] = value
            self.logger.info(f"Updated local data via gossip: {key}={value}")
            
            # Add to our gossip queue with reduced excitement
            new_message = GossipMessage(
                id=message.id,
                data=message.data,
                timestamp=message.timestamp,
                sender_id=message.sender_id,
                excitement_level=max(1, message.excitement_level - 1),
                propagation_count=message.propagation_count + 1,  # Increment propagation count
                recipients_seen=set(message.recipients_seen)
            )
            
            # Always add to queue if not already present
            if not any(m.id == message.id for m in self.gossip_queue):
                self.gossip_queue.append(new_message)
                self.logger.info(f"Added message to gossip queue: {message.id}")

    def join_cluster(self, seed_nodes: List[Tuple[str, int]]):
        """Join the gossip cluster using seed nodes"""
        for host, port in seed_nodes:
            try:
                # Register with seed node
                response = requests.post(
                    f"http://{host}:{port}/api/join",
                    json={
                        'node_id': self.node_id,
                        'host': self.host,
                        'port': self.web_port
                    },
                    timeout=2.0
                )
                
                if response.status_code == 200:
                    self.logger.info(f"Successfully joined cluster via {host}:{port}")
                    # No need to add seed node here; it will be added via sync_members
                    break
                    
            except Exception as e:
                self.logger.warning(f"Failed to connect to seed {host}:{port}: {e}")
                continue

    def setup_routes(self):
        """Setup Flask routes for web interface and API"""
        
        @self.app.route('/')
        def index():
            return render_template_string(self.get_web_template())
        
        @self.app.route('/api/status')
        def status():
            def member_to_dict(v):
                return {
                    'id': v.id,
                    'host': v.host,
                    'port': v.port,
                    'is_alive': v.is_alive,
                    'last_seen': v.last_seen,
                    'vector_clock': dict(v.vector_clock)
                }
            return jsonify({
                'node_id': self.node_id,
                'members': {k: member_to_dict(v) for k, v in self.members.items()},
                'gossip_queue_size': len(self.gossip_queue),
                'local_data': self.local_data,
                'stats': self.stats,
                'vector_clock': dict(self.vector_clock)
            })
        
        @self.app.route('/api/join', methods=['POST'])
        def join():
            try:
                data = request.json
                new_node_id = data.get('node_id')
                new_host = data.get('host')
                new_port = data.get('port')
                
                # Add new node to members using node_id as key
                self.members[new_node_id] = NodeState(
                    id=new_node_id,
                    host=new_host,
                    port=new_port,
                    last_seen=time.time()
                )
                
                # Debug: print current member list
                self.logger.info(f"[JOIN] Current members after join: {list(self.members.keys())}")
                
                # Send our member list to the new node
                response = requests.post(
                    f"http://{new_host}:{new_port}/api/sync_members",
                    json={
                        'members': {k: asdict(v) for k, v in self.members.items()}
                    },
                    timeout=2.0
                )
                
                if response.status_code == 200:
                    self.logger.info(f"Successfully added node {new_node_id} to cluster")
                    return jsonify({'status': 'success'})
                else:
                    self.logger.warning(f"Failed to sync members with {new_node_id}")
                    return jsonify({'status': 'error', 'message': 'Failed to sync members'}), 500
                    
            except Exception as e:
                self.logger.error(f"Error handling join request: {e}")
                return jsonify({'status': 'error', 'message': str(e)}), 400
        
        @self.app.route('/api/sync_members', methods=['POST'])
        def sync_members():
            try:
                data = request.json
                members_data = data.get('members', {})
                
                # Update our member list using node_id as key
                for node_id, member_data in members_data.items():
                    if node_id != self.node_id:  # Don't overwrite self
                        self.members[node_id] = NodeState(
                            id=node_id,
                            host=member_data['host'],
                            port=member_data['port'],
                            is_alive=member_data['is_alive'],
                            last_seen=member_data['last_seen'],
                            vector_clock=member_data['vector_clock']
                        )
                
                # Debug: print current member list
                self.logger.info(f"[SYNC] Current members after sync: {list(self.members.keys())}")
                
                self.logger.info(f"Synced members list, now have {len(self.members)} members")
                return jsonify({'status': 'success'})
                
            except Exception as e:
                self.logger.error(f"Error syncing members: {e}")
                return jsonify({'status': 'error', 'message': str(e)}), 400
        
        @self.app.route('/api/gossip', methods=['POST'])
        def receive_gossip():
            try:
                data = request.json
                message = GossipMessage(**data)
                self.handle_gossip_message(message)
                return jsonify({'status': 'success'})
            except Exception as e:
                self.logger.error(f"Error handling gossip: {e}")
                return jsonify({'status': 'error', 'message': str(e)}), 400
        
        @self.app.route('/api/ping', methods=['POST'])
        def ping():
            return jsonify({
                'status': 'alive',
                'node_id': self.node_id,
                'timestamp': time.time()
            })
        
        @self.app.route('/api/add_data', methods=['POST'])
        def add_data():
            try:
                data = request.json
                key = data.get('key')
                value = data.get('value')
                
                # Update local data and vector clock
                self.local_data[key] = value
                self.vector_clock[self.node_id] += 1
                
                # Create gossip message
                gossip_msg = GossipMessage(
                    id=str(uuid.uuid4()),
                    data={'key': key, 'value': value, 'operation': 'update'},
                    timestamp=time.time(),
                    sender_id=self.node_id,
                    excitement_level=self.max_excitement
                )
                
                self.gossip_queue.append(gossip_msg)
                self.logger.info(f"Added data: {key}={value}, queued for gossip")
                
                return jsonify({'status': 'success', 'key': key, 'value': value})
            except Exception as e:
                return jsonify({'status': 'error', 'message': str(e)}), 400 