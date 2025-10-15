CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Geofence zones table
CREATE TABLE geofence_zones (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    zone_type VARCHAR(50) NOT NULL,
    geometry GEOMETRY(POLYGON, 4326) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT true
);

-- Create spatial index
CREATE INDEX idx_geofence_zones_geom ON geofence_zones USING GIST (geometry);

-- Sample delivery zones for major cities
INSERT INTO geofence_zones (name, zone_type, geometry) VALUES
('Manhattan Financial District', 'delivery_zone', ST_GeomFromText('POLYGON((-74.0085 40.7061, -74.0085 40.7161, -73.9985 40.7161, -73.9985 40.7061, -74.0085 40.7061))', 4326)),
('Brooklyn Heights', 'delivery_zone', ST_GeomFromText('POLYGON((-74.0000 40.6900, -74.0000 40.7000, -73.9900 40.7000, -73.9900 40.6900, -74.0000 40.6900))', 4326)),
('Central Park Area', 'restricted_zone', ST_GeomFromText('POLYGON((-73.9812 40.7681, -73.9812 40.7831, -73.9481 40.7831, -73.9481 40.7681, -73.9812 40.7681))', 4326));

-- Points of Interest table
CREATE TABLE points_of_interest (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100) NOT NULL,
    location GEOMETRY(POINT, 4326) NOT NULL,
    rating DECIMAL(3,2) DEFAULT 0.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_poi_location ON points_of_interest USING GIST (location);

-- Sample restaurants and stores
INSERT INTO points_of_interest (name, category, location, rating) VALUES
('Joe''s Pizza', 'restaurant', ST_SetSRID(ST_MakePoint(-74.0060, 40.7128), 4326), 4.5),
('Central Deli', 'restaurant', ST_SetSRID(ST_MakePoint(-73.9857, 40.7484), 4326), 4.2),
('Brooklyn Bagels', 'restaurant', ST_SetSRID(ST_MakePoint(-73.9950, 40.6950), 4326), 4.7),
('Tech Store', 'electronics', ST_SetSRID(ST_MakePoint(-74.0050, 40.7150), 4326), 4.1),
('Book Corner', 'bookstore', ST_SetSRID(ST_MakePoint(-73.9800, 40.7600), 4326), 4.4);
