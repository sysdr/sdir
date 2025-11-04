const { Kafka } = require('kafkajs');
const faker = require('faker');

const kafka = new Kafka({
  clientId: 'event-generator',
  brokers: [process.env.KAFKA_BOOTSTRAP_SERVERS]
});

const producer = kafka.producer();

const EVENT_TYPES = ['click', 'view', 'purchase', 'signup', 'login'];
const USER_SEGMENTS = ['premium', 'standard', 'trial'];

async function generateEvent() {
  const event = {
    eventId: faker.datatype.uuid(),
    userId: faker.datatype.number({ min: 1, max: 10000 }),
    eventType: faker.random.arrayElement(EVENT_TYPES),
    productId: faker.datatype.number({ min: 1, max: 1000 }),
    timestamp: new Date().toISOString(),
    userSegment: faker.random.arrayElement(USER_SEGMENTS),
    sessionId: faker.datatype.uuid(),
    amount: faker.datatype.float({ min: 10, max: 500, precision: 0.01 }),
    metadata: {
      browser: faker.internet.userAgent(),
      country: faker.address.countryCode(),
      device: faker.random.arrayElement(['mobile', 'desktop', 'tablet'])
    }
  };
  
  return event;
}

async function startGenerator() {
  await producer.connect();
  console.log('📡 Event generator started...');
  
  setInterval(async () => {
    const event = await generateEvent();
    
    await producer.send({
      topic: 'user-events',
      messages: [{
        key: event.userId.toString(),
        value: JSON.stringify(event),
        partition: event.userId % 3
      }]
    });
    
    console.log(`Generated: ${event.eventType} by user ${event.userId}`);
  }, 100); // Generate event every 100ms (10 events/sec)
}

startGenerator().catch(console.error);
