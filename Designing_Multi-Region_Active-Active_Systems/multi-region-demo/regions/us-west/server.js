const RegionNode = require('../../shared/region-node');

const node = new RegionNode(
  'us-west',
  3002,
  ['us-east:3001', 'eu-west:3003']
);

node.start();
