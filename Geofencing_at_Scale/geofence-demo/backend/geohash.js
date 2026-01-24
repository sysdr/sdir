// Geohash implementation for spatial indexing
const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

export class Geohash {
  static encode(lat, lon, precision = 8) {
    let idx = 0;
    let bit = 0;
    let evenBit = true;
    let geohash = '';

    let latMin = -90, latMax = 90;
    let lonMin = -180, lonMax = 180;

    while (geohash.length < precision) {
      if (evenBit) {
        const lonMid = (lonMin + lonMax) / 2;
        if (lon > lonMid) {
          idx |= (1 << (4 - bit));
          lonMin = lonMid;
        } else {
          lonMax = lonMid;
        }
      } else {
        const latMid = (latMin + latMax) / 2;
        if (lat > latMid) {
          idx |= (1 << (4 - bit));
          latMin = latMid;
        } else {
          latMax = latMid;
        }
      }

      evenBit = !evenBit;

      if (bit < 4) {
        bit++;
      } else {
        geohash += BASE32[idx];
        bit = 0;
        idx = 0;
      }
    }

    return geohash;
  }

  static decode(geohash) {
    let evenBit = true;
    let latMin = -90, latMax = 90;
    let lonMin = -180, lonMax = 180;

    for (const char of geohash) {
      const idx = BASE32.indexOf(char);
      
      for (let i = 4; i >= 0; i--) {
        const bit = (idx >> i) & 1;
        
        if (evenBit) {
          const lonMid = (lonMin + lonMax) / 2;
          if (bit === 1) {
            lonMin = lonMid;
          } else {
            lonMax = lonMid;
          }
        } else {
          const latMid = (latMin + latMax) / 2;
          if (bit === 1) {
            latMin = latMid;
          } else {
            latMax = latMid;
          }
        }
        
        evenBit = !evenBit;
      }
    }

    return {
      lat: (latMin + latMax) / 2,
      lon: (lonMin + lonMax) / 2,
      latError: (latMax - latMin) / 2,
      lonError: (lonMax - lonMin) / 2
    };
  }

  static neighbors(geohash) {
    const decoded = this.decode(geohash);
    const precision = geohash.length;
    
    return [
      this.encode(decoded.lat + decoded.latError * 2, decoded.lon, precision), // N
      this.encode(decoded.lat + decoded.latError * 2, decoded.lon + decoded.lonError * 2, precision), // NE
      this.encode(decoded.lat, decoded.lon + decoded.lonError * 2, precision), // E
      this.encode(decoded.lat - decoded.latError * 2, decoded.lon + decoded.lonError * 2, precision), // SE
      this.encode(decoded.lat - decoded.latError * 2, decoded.lon, precision), // S
      this.encode(decoded.lat - decoded.latError * 2, decoded.lon - decoded.lonError * 2, precision), // SW
      this.encode(decoded.lat, decoded.lon - decoded.lonError * 2, precision), // W
      this.encode(decoded.lat + decoded.latError * 2, decoded.lon - decoded.lonError * 2, precision), // NW
    ];
  }
}

export class GeohashIndex {
  constructor(precision = 6) {
    this.precision = precision;
    this.index = new Map(); // geohash -> array of objects
  }

  insert(lat, lon, data) {
    const hash = Geohash.encode(lat, lon, this.precision);
    if (!this.index.has(hash)) {
      this.index.set(hash, []);
    }
    this.index.get(hash).push({ lat, lon, data });
  }

  query(centerLat, centerLon, radiusKm) {
    const centerHash = Geohash.encode(centerLat, centerLon, this.precision);
    const neighbors = Geohash.neighbors(centerHash);
    const searchHashes = [centerHash, ...neighbors];

    const results = [];
    for (const hash of searchHashes) {
      if (this.index.has(hash)) {
        for (const obj of this.index.get(hash)) {
          const distance = this.haversineDistance(centerLat, centerLon, obj.lat, obj.lon);
          if (distance <= radiusKm) {
            results.push({ ...obj, distance });
          }
        }
      }
    }

    return results;
  }

  haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371; // Earth radius in km
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  getStats() {
    let totalObjects = 0;
    const distribution = {};
    
    for (const [hash, objects] of this.index.entries()) {
      totalObjects += objects.length;
      distribution[hash] = objects.length;
    }

    return {
      totalCells: this.index.size,
      totalObjects,
      avgObjectsPerCell: totalObjects / this.index.size || 0,
      distribution
    };
  }
}
