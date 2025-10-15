import React, { useState, useEffect, useCallback } from 'react';
import { Layout, Card, Row, Col, Statistic, Button, Input, message, Space, Tag, Tabs } from 'antd';
import { EnvironmentOutlined, CarOutlined, ShopOutlined, ReloadOutlined } from '@ant-design/icons';
import { MapContainer, TileLayer, Marker, Popup, Polygon, Circle } from 'react-leaflet';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, BarChart, Bar } from 'recharts';
import axios from 'axios';
import io from 'socket.io-client';
import L from 'leaflet';

// Fix for default marker icons
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
  iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
});

const { Header, Content } = Layout;
const { TabPane } = Tabs;

// Custom icons for different marker types
const driverIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-blue.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41]
});

const poiIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41]
});

function App() {
  const [drivers, setDrivers] = useState([]);
  const [geofences, setGeofences] = useState([]);
  const [nearbyResults, setNearbyResults] = useState([]);
  const [metrics, setMetrics] = useState({});
  const [searchLocation, setSearchLocation] = useState({ lat: 40.7128, lon: -74.0060 });
  const [socket, setSocket] = useState(null);
  const [performanceData, setPerformanceData] = useState([]);
  const [searchRadius, setSearchRadius] = useState(1000);
  const [loading, setLoading] = useState(false);

  // NYC center coordinates
  const nycCenter = [40.7128, -74.0060];

  // Initialize WebSocket connection
  useEffect(() => {
    const newSocket = io('http://localhost:8000');
    
    newSocket.on('connect', () => {
      console.log('Connected to WebSocket');
      newSocket.emit('joinTracking', {});
    });

    newSocket.on('locationUpdate', (data) => {
      setDrivers(prev => {
        const updated = prev.filter(d => d.id !== data.driverId);
        updated.push({
          id: data.driverId,
          lat: data.lat,
          lon: data.lon,
          status: data.status || 'available',
          speed: data.speed || 0
        });
        return updated;
      });
    });

    setSocket(newSocket);

    return () => {
      newSocket.close();
    };
  }, []);

  // Load initial data
  useEffect(() => {
    loadGeofences();
    loadMetrics();
    const interval = setInterval(loadMetrics, 5000);
    return () => clearInterval(interval);
  }, []);

  const loadGeofences = async () => {
    try {
      const response = await axios.get('http://localhost:8003/api/geofence/zones');
      setGeofences(Array.isArray(response.data) ? response.data : []);
    } catch (error) {
      console.error('Error loading geofences:', error);
      message.error('Failed to load geofences');
      setGeofences([]); // Ensure it's always an array
    }
  };

  const loadMetrics = async () => {
    try {
      const [locationMetrics, proximityMetrics, geofenceStats] = await Promise.all([
        axios.get('http://localhost:8000/api/metrics'),
        axios.get('http://localhost:8002/api/proximity/metrics'),
        axios.get('http://localhost:8003/api/geofence/stats')
      ]);

      setMetrics({
        location: locationMetrics.data,
        proximity: proximityMetrics.data,
        geofence: geofenceStats.data
      });

      // Add to performance data for charts
      setPerformanceData(prev => {
        const newData = [
          ...prev,
          {
            timestamp: new Date().toLocaleTimeString(),
            drivers: locationMetrics.data.totalDrivers,
            updates: locationMetrics.data.totalUpdates,
            queries: proximityMetrics.data.query_count
          }
        ].slice(-20); // Keep last 20 data points
        return newData;
      });

    } catch (error) {
      console.error('Error loading metrics:', error);
    }
  };

  const searchNearby = async () => {
    setLoading(true);
    try {
      const response = await axios.get(`http://localhost:8000/api/location/nearby`, {
        params: {
          lat: searchLocation.lat,
          lon: searchLocation.lon,
          radius: searchRadius
        }
      });
      
      setNearbyResults(response.data.drivers || []);
      message.success(`Found ${response.data.total} nearby drivers`);
    } catch (error) {
      console.error('Error searching nearby:', error);
      message.error('Failed to search nearby drivers');
    }
    setLoading(false);
  };

  const testKNN = async () => {
    setLoading(true);
    try {
      const response = await axios.post('http://localhost:8002/api/proximity/knn', {
        lat: searchLocation.lat,
        lon: searchLocation.lon,
        k: 5
      });
      
      setNearbyResults(response.data.k_nearest || []);
      message.success(`Found ${response.data.total} nearest drivers`);
    } catch (error) {
      console.error('Error in KNN search:', error);
      message.error('Failed to perform KNN search');
    }
    setLoading(false);
  };

  const checkGeofence = async () => {
    try {
      const response = await axios.get(`http://localhost:8003/api/geofence/check`, {
        params: {
          lat: searchLocation.lat,
          lon: searchLocation.lon
        }
      });
      
      const result = response.data;
      if (result.is_inside_any) {
        const zoneNames = result.inside_zones.map(z => z.name).join(', ');
        message.info(`Location is inside: ${zoneNames}`);
      } else {
        message.info('Location is not inside any geofence zone');
      }
    } catch (error) {
      console.error('Error checking geofence:', error);
      message.error('Failed to check geofence');
    }
  };

  return (
    <Layout style={{ minHeight: '100vh', background: '#f0f2f5' }}>
      <Header style={{ 
        background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)', 
        padding: '0 24px',
        display: 'flex',
        alignItems: 'center'
      }}>
        <h1 style={{ color: 'white', margin: 0, fontSize: '24px', fontWeight: 'bold' }}>
          🌍 Geospatial System Dashboard
        </h1>
      </Header>
      
      <Content style={{ padding: '24px' }}>
        <Row gutter={[24, 24]}>
          {/* Metrics Cards */}
          <Col span={6}>
            <Card style={{ borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}>
              <Statistic
                title="Active Drivers"
                value={metrics.location?.totalDrivers || 0}
                prefix={<CarOutlined style={{ color: '#1890ff' }} />}
                valueStyle={{ color: '#1890ff' }}
              />
            </Card>
          </Col>
          <Col span={6}>
            <Card style={{ borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}>
              <Statistic
                title="Location Updates"
                value={metrics.location?.totalUpdates || 0}
                prefix={<EnvironmentOutlined style={{ color: '#52c41a' }} />}
                valueStyle={{ color: '#52c41a' }}
              />
            </Card>
          </Col>
          <Col span={6}>
            <Card style={{ borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}>
              <Statistic
                title="Geofence Zones"
                value={metrics.geofence?.active_zones || 0}
                prefix={<ShopOutlined style={{ color: '#faad14' }} />}
                valueStyle={{ color: '#faad14' }}
              />
            </Card>
          </Col>
          <Col span={6}>
            <Card style={{ borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}>
              <Statistic
                title="Proximity Queries"
                value={metrics.proximity?.query_count || 0}
                prefix={<ReloadOutlined style={{ color: '#eb2f96' }} />}
                valueStyle={{ color: '#eb2f96' }}
              />
            </Card>
          </Col>
        </Row>

        <Row gutter={[24, 24]} style={{ marginTop: '24px' }}>
          {/* Control Panel */}
          <Col span={8}>
            <Card 
              title="🎯 Spatial Query Controls" 
              style={{ borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}
            >
              <Space direction="vertical" style={{ width: '100%' }}>
                <div>
                  <label style={{ fontWeight: 'bold', marginBottom: '8px', display: 'block' }}>
                    Search Location (Lat, Lon):
                  </label>
                  <Input.Group compact>
                    <Input
                      style={{ width: '50%' }}
                      placeholder="Latitude"
                      value={searchLocation.lat}
                      onChange={(e) => setSearchLocation({
                        ...searchLocation,
                        lat: parseFloat(e.target.value) || 0
                      })}
                    />
                    <Input
                      style={{ width: '50%' }}
                      placeholder="Longitude"
                      value={searchLocation.lon}
                      onChange={(e) => setSearchLocation({
                        ...searchLocation,
                        lon: parseFloat(e.target.value) || 0
                      })}
                    />
                  </Input.Group>
                </div>
                
                <div>
                  <label style={{ fontWeight: 'bold', marginBottom: '8px', display: 'block' }}>
                    Search Radius (meters):
                  </label>
                  <Input
                    type="number"
                    value={searchRadius}
                    onChange={(e) => setSearchRadius(parseInt(e.target.value) || 1000)}
                    placeholder="1000"
                  />
                </div>

                <Space>
                  <Button 
                    type="primary" 
                    onClick={searchNearby}
                    loading={loading}
                    style={{ background: '#1890ff', borderColor: '#1890ff' }}
                  >
                    Search Nearby
                  </Button>
                  <Button 
                    onClick={testKNN}
                    loading={loading}
                    style={{ background: '#52c41a', borderColor: '#52c41a', color: 'white' }}
                  >
                    K-NN Search
                  </Button>
                </Space>

                <Button 
                  onClick={checkGeofence}
                  style={{ width: '100%', background: '#faad14', borderColor: '#faad14', color: 'white' }}
                >
                  Check Geofence
                </Button>
              </Space>
            </Card>

            {/* Search Results */}
            <Card 
              title="🔍 Search Results" 
              style={{ marginTop: '16px', borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}
            >
              <div style={{ maxHeight: '300px', overflowY: 'auto' }}>
                {nearbyResults.map((driver, index) => (
                  <div key={index} style={{ 
                    marginBottom: '12px', 
                    padding: '12px', 
                    background: '#f8f9fa', 
                    borderRadius: '8px',
                    border: '1px solid #e9ecef'
                  }}>
                    <div style={{ fontWeight: 'bold', color: '#1890ff' }}>
                      Driver {driver.id}
                    </div>
                    <div style={{ fontSize: '12px', color: '#666' }}>
                      Distance: {Math.round(driver.distance || 0)}m
                    </div>
                    <div style={{ fontSize: '12px', color: '#666' }}>
                      Status: <Tag color={driver.status === 'available' ? 'green' : 'orange'}>
                        {driver.status}
                      </Tag>
                    </div>
                  </div>
                ))}
              </div>
            </Card>
          </Col>

          {/* Map */}
          <Col span={16}>
            <Card 
              title="🗺️ Real-time Geospatial Map" 
              style={{ borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}
            >
              <div style={{ height: '500px' }}>
                <MapContainer
                  center={nycCenter}
                  zoom={12}
                  style={{ height: '100%', width: '100%', borderRadius: '8px' }}
                >
                  <TileLayer
                    url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                    attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                  />
                  
                  {/* Driver markers */}
                  {drivers.map((driver) => (
                    <Marker 
                      key={driver.id} 
                      position={[driver.lat, driver.lon]}
                      icon={driverIcon}
                    >
                      <Popup>
                        <div style={{ textAlign: 'center' }}>
                          <strong>Driver {driver.id}</strong><br/>
                          Status: <Tag color={driver.status === 'available' ? 'green' : 'orange'}>
                            {driver.status}
                          </Tag><br/>
                          Speed: {Math.round(driver.speed || 0)} km/h<br/>
                          Location: {driver.lat.toFixed(4)}, {driver.lon.toFixed(4)}
                        </div>
                      </Popup>
                    </Marker>
                  ))}

                  {/* Search center marker */}
                  <Marker position={[searchLocation.lat, searchLocation.lon]}>
                    <Popup>
                      <div style={{ textAlign: 'center' }}>
                        <strong>Search Center</strong><br/>
                        {searchLocation.lat.toFixed(4)}, {searchLocation.lon.toFixed(4)}
                      </div>
                    </Popup>
                  </Marker>

                  {/* Search radius circle */}
                  <Circle
                    center={[searchLocation.lat, searchLocation.lon]}
                    radius={searchRadius}
                    pathOptions={{ color: '#1890ff', fillColor: '#1890ff', fillOpacity: 0.1 }}
                  />

                  {/* Geofence zones */}
                  {Array.isArray(geofences) && geofences.map((zone) => (
                    <Polygon
                      key={zone.id}
                      positions={zone.coordinates}
                      pathOptions={{
                        color: zone.zone_type === 'delivery_zone' ? '#52c41a' : '#f5222d',
                        fillColor: zone.zone_type === 'delivery_zone' ? '#52c41a' : '#f5222d',
                        fillOpacity: 0.2,
                        weight: 2
                      }}
                    >
                      <Popup>
                        <div style={{ textAlign: 'center' }}>
                          <strong>{zone.name}</strong><br/>
                          Type: <Tag color={zone.zone_type === 'delivery_zone' ? 'green' : 'red'}>
                            {zone.zone_type}
                          </Tag>
                        </div>
                      </Popup>
                    </Polygon>
                  ))}
                </MapContainer>
              </div>
            </Card>
          </Col>
        </Row>

        {/* Performance Charts */}
        <Row gutter={[24, 24]} style={{ marginTop: '24px' }}>
          <Col span={12}>
            <Card 
              title="📈 Real-time Performance Metrics" 
              style={{ borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}
            >
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={performanceData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="timestamp" />
                  <YAxis />
                  <Tooltip />
                  <Line type="monotone" dataKey="drivers" stroke="#1890ff" strokeWidth={2} />
                  <Line type="monotone" dataKey="queries" stroke="#52c41a" strokeWidth={2} />
                </LineChart>
              </ResponsiveContainer>
            </Card>
          </Col>
          
          <Col span={12}>
            <Card 
              title="📊 Geofence Zone Distribution" 
              style={{ borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}
            >
              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={[
                  { name: 'Delivery Zones', count: metrics.geofence?.delivery_zones || 0 },
                  { name: 'Restricted Zones', count: metrics.geofence?.restricted_zones || 0 },
                  { name: 'Total Zones', count: metrics.geofence?.total_zones || 0 }
                ]}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="name" />
                  <YAxis />
                  <Tooltip />
                  <Bar dataKey="count" fill="#1890ff" />
                </BarChart>
              </ResponsiveContainer>
            </Card>
          </Col>
        </Row>
      </Content>
    </Layout>
  );
}

export default App;
