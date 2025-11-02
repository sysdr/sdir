from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
import asyncpg
import redis.asyncio as redis
import json
from typing import List, Optional, Dict, Any
from pydantic import BaseModel
from shapely.geometry import Point, Polygon
from shapely.wkt import loads as wkt_loads
import asyncio
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Geofence Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Models
class GeofenceZone(BaseModel):
    id: Optional[int] = None
    name: str
    zone_type: str
    coordinates: List[List[float]]  # [[lat, lon], [lat, lon], ...]
    is_active: bool = True

class LocationPoint(BaseModel):
    lat: float
    lon: float

class GeofenceCheck(BaseModel):
    point: LocationPoint
    zone_ids: Optional[List[int]] = None

# Database connection
DATABASE_URL = "postgresql://geo_user:geo_pass@postgres:5432/geospatial"
REDIS_URL = "redis://redis:6379"

class GeofenceManager:
    def __init__(self):
        self.db_pool = None
        self.redis_client = None

    async def init_connections(self):
        self.db_pool = await asyncpg.create_pool(DATABASE_URL, min_size=5, max_size=20)
        self.redis_client = redis.from_url(REDIS_URL)
        logger.info("Database and Redis connections initialized")

    async def create_zone(self, zone: GeofenceZone) -> Dict[str, Any]:
        """Create a new geofence zone"""
        try:
            # Convert coordinates to PostGIS polygon format
            polygon_points = [(lon, lat) for lat, lon in zone.coordinates]
            polygon_points.append(polygon_points[0])  # Close the polygon
            
            wkt_polygon = f"POLYGON(({', '.join([f'{lon} {lat}' for lon, lat in polygon_points])}))"
            
            async with self.db_pool.acquire() as conn:
                zone_id = await conn.fetchval(
                    """
                    INSERT INTO geofence_zones (name, zone_type, geometry, is_active)
                    VALUES ($1, $2, ST_GeomFromText($3, 4326), $4)
                    RETURNING id
                    """,
                    zone.name, zone.zone_type, wkt_polygon, zone.is_active
                )
                
                # Cache zone in Redis for fast lookups
                zone_data = {
                    "id": zone_id,
                    "name": zone.name,
                    "zone_type": zone.zone_type,
                    "coordinates": zone.coordinates,
                    "is_active": zone.is_active
                }
                await self.redis_client.hset(f"zone:{zone_id}", mapping=zone_data)
                
                return zone_data
                
        except Exception as e:
            logger.error(f"Error creating zone: {e}")
            raise HTTPException(status_code=500, detail=str(e))

    async def get_all_zones(self) -> List[Dict[str, Any]]:
        """Get all geofence zones"""
        try:
            async with self.db_pool.acquire() as conn:
                rows = await conn.fetch(
                    """
                    SELECT id, name, zone_type, 
                           ST_AsText(geometry) as geometry_wkt,
                           is_active, created_at
                    FROM geofence_zones
                    WHERE is_active = true
                    ORDER BY created_at DESC
                    """
                )
                
                zones = []
                for row in rows:
                    # Parse WKT polygon to coordinates
                    polygon = wkt_loads(row['geometry_wkt'])
                    coordinates = [[lat, lon] for lon, lat in polygon.exterior.coords[:-1]]
                    
                    zones.append({
                        "id": row['id'],
                        "name": row['name'],
                        "zone_type": row['zone_type'],
                        "coordinates": coordinates,
                        "is_active": row['is_active'],
                        "created_at": row['created_at'].isoformat()
                    })
                
                return zones
                
        except Exception as e:
            logger.error(f"Error getting zones: {e}")
            raise HTTPException(status_code=500, detail=str(e))

    async def check_point_in_zones(self, lat: float, lon: float, zone_ids: Optional[List[int]] = None) -> Dict[str, Any]:
        """Check if a point is inside geofence zones"""
        try:
            point_wkt = f"POINT({lon} {lat})"
            
            async with self.db_pool.acquire() as conn:
                if zone_ids:
                    # Check specific zones
                    query = """
                        SELECT id, name, zone_type,
                               ST_Contains(geometry, ST_GeomFromText($1, 4326)) as contains
                        FROM geofence_zones
                        WHERE id = ANY($2) AND is_active = true
                    """
                    rows = await conn.fetch(query, point_wkt, zone_ids)
                else:
                    # Check all active zones
                    query = """
                        SELECT id, name, zone_type,
                               ST_Contains(geometry, ST_GeomFromText($1, 4326)) as contains
                        FROM geofence_zones
                        WHERE is_active = true
                    """
                    rows = await conn.fetch(query, point_wkt)
                
                inside_zones = [
                    {
                        "id": row['id'],
                        "name": row['name'],
                        "zone_type": row['zone_type']
                    }
                    for row in rows if row['contains']
                ]
                
                result = {
                    "point": {"lat": lat, "lon": lon},
                    "inside_zones": inside_zones,
                    "total_zones_checked": len(rows),
                    "is_inside_any": len(inside_zones) > 0
                }
                
                # Cache result for 30 seconds
                cache_key = f"geofence_check:{lat:.6f}:{lon:.6f}"
                await self.redis_client.setex(cache_key, 30, json.dumps(result))
                
                return result
                
        except Exception as e:
            logger.error(f"Error checking geofence: {e}")
            raise HTTPException(status_code=500, detail=str(e))

    async def get_statistics(self) -> Dict[str, Any]:
        """Get geofence statistics"""
        try:
            async with self.db_pool.acquire() as conn:
                stats = await conn.fetchrow(
                    """
                    SELECT 
                        COUNT(*) as total_zones,
                        COUNT(CASE WHEN is_active THEN 1 END) as active_zones,
                        COUNT(CASE WHEN zone_type = 'delivery_zone' THEN 1 END) as delivery_zones,
                        COUNT(CASE WHEN zone_type = 'restricted_zone' THEN 1 END) as restricted_zones
                    FROM geofence_zones
                    """
                )
                
                return dict(stats)
                
        except Exception as e:
            logger.error(f"Error getting statistics: {e}")
            return {"error": str(e)}

geofence_manager = GeofenceManager()

@app.on_event("startup")
async def startup_event():
    await geofence_manager.init_connections()

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "geofence-service"}

@app.post("/api/geofence/zones")
async def create_geofence_zone(zone: GeofenceZone):
    """Create a new geofence zone"""
    return await geofence_manager.create_zone(zone)

@app.get("/api/geofence/zones")
async def get_geofence_zones():
    """Get all geofence zones"""
    return await geofence_manager.get_all_zones()

@app.post("/api/geofence/check")
async def check_geofence(check: GeofenceCheck):
    """Check if a point is inside geofence zones"""
    return await geofence_manager.check_point_in_zones(
        check.point.lat, 
        check.point.lon, 
        check.zone_ids
    )

@app.get("/api/geofence/check")
async def check_geofence_get(
    lat: float = Query(..., description="Latitude"),
    lon: float = Query(..., description="Longitude"),
    zone_ids: Optional[str] = Query(None, description="Comma-separated zone IDs")
):
    """Check if a point is inside geofence zones (GET method)"""
    zone_id_list = None
    if zone_ids:
        zone_id_list = [int(id.strip()) for id in zone_ids.split(",")]
    
    return await geofence_manager.check_point_in_zones(lat, lon, zone_id_list)

@app.get("/api/geofence/stats")
async def get_geofence_statistics():
    """Get geofence statistics"""
    return await geofence_manager.get_statistics()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
