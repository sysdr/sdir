const RegionNode = require('../../shared/region-node');

const node = new RegionNode(
  'eu-west',
  3003,
  ['us-east:3001', 'us-west:3002']
);

node.start();
