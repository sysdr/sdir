import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import { ApolloGateway, IntrospectAndCompose } from '@apollo/gateway';
import express from 'express';
import cors from 'cors';

const gateway = new ApolloGateway({
  supergraphSdl: new IntrospectAndCompose({
    subgraphs: [
      { name: 'users', url: 'http://localhost:4001/graphql' },
      { name: 'products', url: 'http://localhost:4002/graphql' },
      { name: 'reviews', url: 'http://localhost:4003/graphql' }
    ],
    pollIntervalInMs: 10000
  }),
  experimental_didResolveQueryPlan: function(options) {
    const plan = options.queryPlan;
    const queryPlanInfo = {
      timestamp: new Date().toISOString(),
      operationName: options.operationContext.operationName,
      services: extractServicesFromPlan(plan),
      parallelSteps: countParallelSteps(plan),
      totalSteps: countTotalSteps(plan)
    };
    console.log('Query Plan:', JSON.stringify(queryPlanInfo, null, 2));
  }
});

function extractServicesFromPlan(plan) {
  const services = new Set();
  JSON.stringify(plan, (key, value) => {
    if (key === 'serviceName') services.add(value);
    return value;
  });
  return Array.from(services);
}

function countParallelSteps(plan) {
  let count = 0;
  JSON.stringify(plan, (key, value) => {
    if (key === 'parallel' && Array.isArray(value)) count++;
    return value;
  });
  return count;
}

function countTotalSteps(plan) {
  let count = 0;
  JSON.stringify(plan, (key, value) => {
    if (key === 'fetch' || key === 'parallel') count++;
    return value;
  });
  return count;
}

const app = express();

const server = new ApolloServer({ gateway });

await server.start();

app.use(
  '/graphql',
  cors(),
  express.json(),
  expressMiddleware(server, {
    context: async ({ req }) => ({ req })
  })
);

app.get('/metrics', (req, res) => {
  res.json({
    gateway: 'running',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

app.listen(4000, () => {
  console.log('🚪 Gateway running at http://localhost:4000/graphql');
});
