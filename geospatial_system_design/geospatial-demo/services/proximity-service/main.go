package main

import (
    "context"
    "fmt"
    "log"
    "math"
    "net/http"
    "os"
    "sort"
    "time"

    "github.com/gin-contrib/cors"
    "github.com/gin-gonic/gin"
    "github.com/go-redis/redis/v8"
)

type ProximityService struct {
    redis *redis.Client
    ctx   context.Context
}

type Location struct {
    ID     string  `json:"id"`
    Lat    float64 `json:"lat"`
    Lon    float64 `json:"lon"`
    Distance float64 `json:"distance,omitempty"`
}

type ProximityRequest struct {
    Lat    float64 `json:"lat" binding:"required"`
    Lon    float64 `json:"lon" binding:"required"`
    Radius float64 `json:"radius"`
    Limit  int     `json:"limit"`
    Type   string  `json:"type"`
}

type KNNRequest struct {
    Lat float64 `json:"lat" binding:"required"`
    Lon float64 `json:"lon" binding:"required"`
    K   int     `json:"k"`
}

func NewProximityService() *ProximityService {
    redisURL := os.Getenv("REDIS_URL")
    if redisURL == "" {
        redisURL = "redis://localhost:6379"
    }

    opt, err := redis.ParseURL(redisURL)
    if err != nil {
        log.Fatal("Failed to parse Redis URL:", err)
    }

    rdb := redis.NewClient(opt)
    
    ctx := context.Background()
    _, err = rdb.Ping(ctx).Result()
    if err != nil {
        log.Fatal("Failed to connect to Redis:", err)
    }

    log.Println("Connected to Redis successfully")
    return &ProximityService{redis: rdb, ctx: ctx}
}

// Haversine formula for calculating distance between two points
func haversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
    const R = 6371000 // Earth's radius in meters

    lat1Rad := lat1 * math.Pi / 180
    lat2Rad := lat2 * math.Pi / 180
    deltaLat := (lat2 - lat1) * math.Pi / 180
    deltaLon := (lon2 - lon1) * math.Pi / 180

    a := math.Sin(deltaLat/2)*math.Sin(deltaLat/2) +
        math.Cos(lat1Rad)*math.Cos(lat2Rad)*
            math.Sin(deltaLon/2)*math.Sin(deltaLon/2)
    c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

    return R * c
}

func (ps *ProximityService) healthCheck(c *gin.Context) {
    c.JSON(http.StatusOK, gin.H{
        "status":  "healthy",
        "service": "proximity-service",
    })
}

func (ps *ProximityService) findNearby(c *gin.Context) {
    var req ProximityRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Default values
    if req.Radius == 0 {
        req.Radius = 5000 // 5km default
    }
    if req.Limit == 0 {
        req.Limit = 50
    }
    if req.Type == "" {
        req.Type = "drivers"
    }

    key := fmt.Sprintf("%s:locations", req.Type)

    // Use Redis GEORADIUS command
    cmd := ps.redis.GeoRadius(ps.ctx, key, req.Lon, req.Lat, &redis.GeoRadiusQuery{
        Radius:      req.Radius,
        Unit:        "m",
        WithCoord:   true,
        WithDist:    true,
        Count:       req.Limit,
        Sort:        "ASC",
    })

    results, err := cmd.Result()
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    var locations []Location
    for _, result := range results {
        locations = append(locations, Location{
            ID:       result.Name,
            Lat:      result.Latitude,
            Lon:      result.Longitude,
            Distance: result.Dist,
        })
    }

    c.JSON(http.StatusOK, gin.H{
        "locations": locations,
        "total":     len(locations),
        "query": gin.H{
            "lat":    req.Lat,
            "lon":    req.Lon,
            "radius": req.Radius,
            "type":   req.Type,
        },
    })
}

func (ps *ProximityService) kNearestNeighbors(c *gin.Context) {
    var req KNNRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    if req.K <= 0 {
        req.K = 5 // Default to 5 nearest neighbors
    }

    // Get all drivers from Redis
    members, err := ps.redis.ZRangeWithScores(ps.ctx, "drivers:locations", 0, -1).Result()
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    type DriverWithDistance struct {
        Location
        GeoHash int64
    }

    var drivers []DriverWithDistance

    // Calculate distances for all drivers
    for _, member := range members {
        // Get coordinates from geohash
        coords, err := ps.redis.GeoPos(ps.ctx, "drivers:locations", member.Member.(string)).Result()
        if err != nil || len(coords) == 0 || coords[0] == nil {
            continue
        }

        lat := coords[0].Latitude
        lon := coords[0].Longitude
        distance := haversineDistance(req.Lat, req.Lon, lat, lon)

        drivers = append(drivers, DriverWithDistance{
            Location: Location{
                ID:       member.Member.(string),
                Lat:      lat,
                Lon:      lon,
                Distance: distance,
            },
            GeoHash: int64(member.Score),
        })
    }

    // Sort by distance
    sort.Slice(drivers, func(i, j int) bool {
        return drivers[i].Distance < drivers[j].Distance
    })

    // Take top K
    if req.K > len(drivers) {
        req.K = len(drivers)
    }

    var kNearest []Location
    for i := 0; i < req.K; i++ {
        kNearest = append(kNearest, drivers[i].Location)
    }

    c.JSON(http.StatusOK, gin.H{
        "k_nearest": kNearest,
        "total":     len(kNearest),
        "query": gin.H{
            "lat": req.Lat,
            "lon": req.Lon,
            "k":   req.K,
        },
    })
}

func (ps *ProximityService) getMetrics(c *gin.Context) {
    // Get total number of drivers
    totalDrivers, err := ps.redis.ZCard(ps.ctx, "drivers:locations").Result()
    if err != nil {
        totalDrivers = 0
    }

    // Get Redis memory usage
    info, err := ps.redis.Info(ps.ctx, "memory").Result()
    var memoryUsage int64 = 0
    if err == nil {
        // Parse memory info (simplified)
        // In production, you'd want more robust parsing
        _ = info // Use info to extract memory stats
    }

    // Calculate query statistics
    queryCount, _ := ps.redis.Get(ps.ctx, "proximity:query_count").Int64()
    avgResponseTime, _ := ps.redis.Get(ps.ctx, "proximity:avg_response_time").Float64()

    c.JSON(http.StatusOK, gin.H{
        "total_drivers":      totalDrivers,
        "memory_usage_bytes": memoryUsage,
        "query_count":        queryCount,
        "avg_response_time":  avgResponseTime,
        "timestamp":          time.Now().Unix(),
    })
}

func (ps *ProximityService) incrementQueryCounter() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        
        c.Next()
        
        // Record metrics
        duration := time.Since(start).Milliseconds()
        ps.redis.Incr(ps.ctx, "proximity:query_count")
        
        // Update average response time (simplified)
        ps.redis.Set(ps.ctx, "proximity:last_response_time", duration, time.Hour)
    }
}

func main() {
    gin.SetMode(gin.ReleaseMode)
    
    ps := NewProximityService()
    
    r := gin.Default()
    
    // CORS middleware
    r.Use(cors.New(cors.Config{
        AllowOrigins:     []string{"*"},
        AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
        AllowHeaders:     []string{"*"},
        ExposeHeaders:    []string{"Content-Length"},
        AllowCredentials: true,
    }))
    
    // Add metrics middleware
    r.Use(ps.incrementQueryCounter())
    
    // Health check
    r.GET("/health", ps.healthCheck)
    
    // API routes
    api := r.Group("/api/proximity")
    {
        api.POST("/nearby", ps.findNearby)
        api.POST("/knn", ps.kNearestNeighbors)
        api.GET("/metrics", ps.getMetrics)
    }
    
    port := os.Getenv("PORT")
    if port == "" {
        port = "8002"
    }
    
    log.Printf("Proximity service starting on port %s", port)
    log.Fatal(r.Run(":" + port))
}
