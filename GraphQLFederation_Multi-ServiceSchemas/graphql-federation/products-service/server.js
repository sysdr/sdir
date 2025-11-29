import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import { buildSubgraphSchema } from '@apollo/subgraph';
import gql from 'graphql-tag';
import express from 'express';
import cors from 'cors';

const products = [
  { id: '101', name: 'Laptop Pro', price: 1299.99, category: 'Electronics' },
  { id: '102', name: 'Wireless Mouse', price: 29.99, category: 'Electronics' },
  { id: '103', name: 'Desk Chair', price: 249.99, category: 'Furniture' },
  { id: '104', name: 'Monitor 27"', price: 399.99, category: 'Electronics' }
];

const typeDefs = gql`
  type Product @key(fields: "id") {
    id: ID!
    name: String!
    price: Float!
    category: String!
  }

  type Query {
    products: [Product!]!
    product(id: ID!): Product
  }
`;

const resolvers = {
  Query: {
    products: () => {
      console.log('Fetching all products');
      return products;
    },
    product: (_, { id }) => {
      console.log(`Fetching product: ${id}`);
      return products.find(p => p.id === id);
    }
  },
  Product: {
    __resolveReference: (reference) => {
      console.log(`Resolving Product entity: ${reference.id}`);
      return products.find(p => p.id === reference.id);
    }
  }
};

const app = express();

const server = new ApolloServer({
  schema: buildSubgraphSchema({ typeDefs, resolvers })
});

await server.start();

app.use(
  '/graphql',
  cors(),
  express.json(),
  expressMiddleware(server)
);

app.listen(4002, () => {
  console.log('📦 Products Service running at http://localhost:4002/graphql');
});
