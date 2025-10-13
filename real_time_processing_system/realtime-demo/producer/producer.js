import { Kafka } from 'kafkajs';

const kafka = new Kafka({
  clientId: 'click-producer',
  brokers: [process.env.KAFKA_BROKER || 'localhost:9092'],
  retry: {
    retries: 10,
    initialRetryTime: 300
  }
});

const producer = kafka.producer();
const TOPIC = 'user-clicks';

const userIds = ['user1', 'user2', 'user3', 'user4', 'user5'];
const pages = ['/home', '/products', '/cart', '/checkout', '/profile'];

async function generateClicks() {
  await producer.connect();
  console.log('✓ Producer connected to Kafka');

  let messageCount = 0;
  setInterval(async () => {
    const clicksInBatch = Math.floor(Math.random() * 10) + 5;
    const messages = [];

    for (let i = 0; i < clicksInBatch; i++) {
      const userId = userIds[Math.floor(Math.random() * userIds.length)];
      const page = pages[Math.floor(Math.random() * pages.length)];
      const timestamp = Date.now();
      
      // Occasionally generate late-arriving events
      const isLate = Math.random() < 0.1;
      const eventTime = isLate ? timestamp - 3000 : timestamp;

      messages.push({
        key: userId,
        value: JSON.stringify({
          userId,
          page,
          timestamp: eventTime,
          eventTime: new Date(eventTime).toISOString(),
          isLateEvent: isLate
        })
      });
    }

    await producer.send({
      topic: TOPIC,
      messages
    });

    messageCount += clicksInBatch;
    console.log(`✓ Sent ${clicksInBatch} clicks (Total: ${messageCount})`);
  }, 1000);
}

generateClicks().catch(console.error);
