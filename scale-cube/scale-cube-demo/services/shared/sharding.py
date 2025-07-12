import hashlib

def get_shard_for_user(user_id: int, num_shards: int = 2) -> int:
    """
    Z-axis scaling: Determine which shard a user belongs to
    Uses consistent hashing for even distribution
    """
    hash_object = hashlib.md5(str(user_id).encode())
    hash_int = int(hash_object.hexdigest(), 16)
    return (hash_int % num_shards) + 1

def get_shard_service_url(shard_id: int) -> str:
    """Get the service URL for a specific shard"""
    return f"http://user_service_{shard_id}:8001"
