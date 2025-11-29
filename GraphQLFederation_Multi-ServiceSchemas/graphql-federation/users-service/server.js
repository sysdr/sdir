import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import { buildSubgraphSchema } from '@apollo/subgraph';
import gql from 'graphql-tag';
import express from 'express';
import cors from 'cors';

const users = [
  { id: '1', name: 'Alice Johnson', email: 'alice@example.com', joinDate: '2023-01-15' },
  { id: '2', name: 'Bob Smith', email: 'bob@example.com', joinDate: '2023-03-22' },
  { id: '3', name: 'Carol White', email: 'carol@example.com', joinDate: '2023-05-10' }
];

const typeDefs = gql`
  type User @key(fields: "id") {
    id: ID!
    name: String!
    email: String!
    joinDate: String!
  }

  type Query {
    users: [User!]!
    user(id: ID!): User
  }
`;

const resolvers = {
  Query: {
    users: () => {
      console.log('Fetching all users');
      return users;
    },
    user: (_, { id }) => {
      console.log(`Fetching user: ${id}`);
      return users.find(u => u.id === id);
    }
  },
  User: {
    __resolveReference: (reference) => {
      console.log(`Resolving User entity: ${reference.id}`);
      return users.find(u => u.id === reference.id);
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

app.listen(4001, () => {
  console.log('👤 Users Service running at http://localhost:4001/graphql');
});
