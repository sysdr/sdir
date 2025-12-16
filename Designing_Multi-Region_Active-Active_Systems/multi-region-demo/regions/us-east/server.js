const RegionNode = require('../../shared/region-node');

const node = new RegionNode(
  'us-east',
  3001,
  ['us-west:3002', 'eu-west:3003']
);

node.start();
