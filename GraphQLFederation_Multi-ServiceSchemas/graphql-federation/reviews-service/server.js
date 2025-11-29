import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import { buildSubgraphSchema } from '@apollo/subgraph';
import gql from 'graphql-tag';
import express from 'express';
import cors from 'cors';

const reviews = [
  { id: '1', productId: '101', userId: '1', rating: 5, comment: 'Excellent laptop!', date: '2024-01-20' },
  { id: '2', productId: '101', userId: '2', rating: 4, comment: 'Great performance', date: '2024-01-22' },
  { id: '3', productId: '102', userId: '1', rating: 5, comment: 'Perfect mouse', date: '2024-02-05' },
  { id: '4', productId: '103', userId: '3', rating: 4, comment: 'Comfortable chair', date: '2024-02-10' },
  { id: '5', productId: '104', userId: '2', rating: 5, comment: 'Crystal clear display', date: '2024-02-15' }
];

const typeDefs = gql`
  type Review {
    id: ID!
    rating: Int!
    comment: String!
    date: String!
    author: User!
  }

  extend type Product @key(fields: "id") {
    id: ID! @external
    reviews: [Review!]!
    avgRating: Float!
    reviewCount: Int!
  }

  extend type User @key(fields: "id") {
    id: ID! @external
    reviews: [Review!]!
  }
`;

const resolvers = {
  Product: {
    reviews: (product) => {
      console.log(`Fetching reviews for product: ${product.id}`);
      return reviews.filter(r => r.productId === product.id);
    },
    avgRating: (product) => {
      const productReviews = reviews.filter(r => r.productId === product.id);
      if (productReviews.length === 0) return 0;
      const sum = productReviews.reduce((acc, r) => acc + r.rating, 0);
      return parseFloat((sum / productReviews.length).toFixed(2));
    },
    reviewCount: (product) => {
      return reviews.filter(r => r.productId === product.id).length;
    }
  },
  User: {
    reviews: (user) => {
      console.log(`Fetching reviews for user: ${user.id}`);
      return reviews.filter(r => r.userId === user.id);
    }
  },
  Review: {
    author: (review) => {
      return { __typename: 'User', id: review.userId };
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

app.listen(4003, () => {
  console.log('⭐ Reviews Service running at http://localhost:4003/graphql');
});
