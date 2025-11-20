import mqtt from 'mqtt';

const MQTT_URL = process.env.MQTT_URL || 'mqtt://mqtt-broker:1883';
const DEVICE_COUNT = parseInt(process.env.DEVICE_COUNT || '5');

const client = mqtt.connect(MQTT_URL);

const devices = [];

client.on('connect', () => {
  console.log(`🔌 Connected to MQTT broker, simulating ${DEVICE_COUNT} devices`);
  
  // Create devices
  for (let i = 1; i <= DEVICE_COUNT; i++) {
    const deviceId = `sensor-${String(i).padStart(3, '0')}`;
    devices.push({
      id: deviceId,
      type: i % 2 === 0 ? 'temperature' : 'humidity',
      baseTemp: 20 + Math.random() * 5,
      baseHumidity: 40 + Math.random() * 20
    });

    // Subscribe to commands
    client.subscribe(`devices/${deviceId}/command`);
  }

  // Send telemetry every 2 seconds
  setInterval(() => {
    devices.forEach(device => {
      const telemetry = {
        device_type: device.type,
        metrics: {
          temperature: device.baseTemp + (Math.random() - 0.5) * 2,
          humidity: device.baseHumidity + (Math.random() - 0.5) * 5,
          battery: 85 + Math.random() * 15
        },
        metadata: {
          firmware: '2.1.0',
          rssi: -50 - Math.random() * 30
        }
      };

      client.publish(
        `devices/${device.id}/telemetry`,
        JSON.stringify(telemetry)
      );
    });
  }, 2000);

  // Send status updates every 10 seconds
  setInterval(() => {
    devices.forEach(device => {
      client.publish(
        `devices/${device.id}/status`,
        JSON.stringify({ status: 'online', uptime: Date.now() })
      );
    });
  }, 10000);
});

// Handle commands
client.on('message', (topic, message) => {
  const parts = topic.split('/');
  const deviceId = parts[1];
  const payload = JSON.parse(message.toString());
  
  console.log(`📥 ${deviceId} received command: ${payload.command}`);
});

console.log('🚀 Device Simulator starting...');
