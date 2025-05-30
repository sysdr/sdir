import hashlib
import random

class VNode:
    def __init__(self, id, token):
        self.id = id
        self.token = token
        self.data = {}
    
    def store(self, key, value):
        self.data[key] = value
    
    def get(self, key):
        return self.data.get(key)

class CassandraRing:
    def __init__(self, num_vnodes=8):
        self.vnodes = []
        # Create vnodes with evenly distributed tokens
        token_step = 2**64 // num_vnodes
        for i in range(num_vnodes):
            token = i * token_step
            self.vnodes.append(VNode(i, token))
        
        # Sort vnodes by token
        self.vnodes.sort(key=lambda x: x.token)
    
    def get_responsible_vnode(self, key):
        # Hash the key to get a token
        key_hash = int(hashlib.md5(str(key).encode()).hexdigest(), 16) % 2**64
        
        # Find the first vnode with token >= key_hash
        for vnode in self.vnodes:
            if vnode.token >= key_hash:
                return vnode
        
        # If no such vnode, wrap around to the first one
        return self.vnodes[0]
    
    def put(self, key, value, replication_factor=3):
        # Find the primary vnode
        primary_vnode = self.get_responsible_vnode(key)
        primary_index = self.vnodes.index(primary_vnode)
        
        # Store on primary and replicas
        for i in range(replication_factor):
            replica_index = (primary_index + i) % len(self.vnodes)
            self.vnodes[replica_index].store(key, value)
        
        return f"Stored {key} on vnode {primary_vnode.id} and {replication_factor-1} replicas"
    
    def get(self, key):
        vnode = self.get_responsible_vnode(key)
        return vnode.get(key)
    
    def simulate_gossip(self, rounds=5):
        for _ in range(rounds):
            # Each node gossips with up to 3 random other nodes
            for vnode in self.vnodes:
                gossip_partners = random.sample(
                    [v for v in self.vnodes if v.id != vnode.id], 
                    min(3, len(self.vnodes)-1)
                )
                for partner in gossip_partners:
                    # In a real implementation, nodes would exchange state here
                    pass

# Example usage
ring = CassandraRing(num_vnodes=8)
print(ring.put("user_123", {"name": "Alice", "email": "alice@example.com"}))
print(ring.get("user_123"))
ring.simulate_gossip()