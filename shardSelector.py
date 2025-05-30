// MongoDB Shard Key Analyzer
// This tool analyzes query patterns from MongoDB logs to suggest optimal shard keys

const fs = require('fs');
const readline = require('readline');
const { MongoClient } = require('mongodb');

// Configuration
const config = {
  logPath: '/var/log/mongodb/mongod.log',
  sampleSize: 10000,
  connectionString: 'mongodb://localhost:27017',
  dbName: 'yourDatabase'
};

// Query pattern analyzer
class ShardKeyAnalyzer {
  constructor() {
    this.queryPatterns = {};
    this.fieldFrequency = {};
    this.collectionStats = {};
  }

  async analyzeLogFile() {
    const fileStream = fs.createReadStream(config.logPath);
    const rl = readline.createInterface({
      input: fileStream,
      crlfDelay: Infinity
    });

    let count = 0;
    for await (const line of rl) {
      if (count >= config.sampleSize) break;
      
      // Extract query patterns from log lines
      const queryMatch = line.match(/query\s+(\w+)\.(\w+)\s+(\{.+\})/);
      if (queryMatch) {
        const [, db, collection, queryString] = queryMatch;
        try {
          const query = JSON.parse(queryString.replace(/([{,])\s*(\w+):/g, '$1"$2":'));
          this.processQuery(collection, query);
          count++;
        } catch (e) {
          // Skip malformed queries
        }
      }
    }
  }

  processQuery(collection, query) {
    // Extract query fields for frequency analysis
    this.extractQueryFields(collection, query);
    
    // Store query pattern
    const key = `${collection}:${JSON.stringify(Object.keys(query).sort())}`;
    this.queryPatterns[key] = (this.queryPatterns[key] || 0) + 1;
  }

  extractQueryFields(collection, obj, prefix = '') {
    for (const [key, value] of Object.entries(obj)) {
      if (key.startsWith(')) continue; // Skip operators
      
      const fieldName = prefix ? `${prefix}.${key}` : key;
      const collectionField = `${collection}:${fieldName}`;
      
      this.fieldFrequency[collectionField] = (this.fieldFrequency[collectionField] || 0) + 1;
      
      // Recurse into nested objects
      if (value && typeof value === 'object' && !Array.isArray(value)) {
        this.extractQueryFields(collection, value, fieldName);
      }
    }
  }

  async gatherCollectionStats() {
    const client = new MongoClient(config.connectionString);
    try {
      await client.connect();
      const db = client.db(config.dbName);
      
      // Get all collections
      const collections = await db.listCollections().toArray();
      
      for (const collInfo of collections) {
        const coll = db.collection(collInfo.name);
        this.collectionStats[collInfo.name] = {
          count: await coll.countDocuments(),
          indexes: await coll.indexes()
        };
      }
    } finally {
      await client.close();
    }
  }

  generateShardKeyRecommendations() {
    const recommendations = {};
    
    // For each collection
    Object.keys(this.collectionStats).forEach(collection => {
      const collectionFields = Object.keys(this.fieldFrequency)
        .filter(key => key.startsWith(`${collection}:`))
        .map(key => ({
          field: key.split(':')[1],
          queryFrequency: this.fieldFrequency[key]
        }))
        .sort((a, b) => b.queryFrequency - a.queryFrequency);

      // Generate recommendations based on query patterns and field cardinality
      recommendations[collection] = {
        highCardinalityFields: collectionFields.slice(0, 3).map(f => f.field),
        recommendedShardKeys: this.buildShardKeyRecommendations(collection, collectionFields)
      };
    });
    
    return recommendations;
  }

  buildShardKeyRecommendations(collection, fieldStats) {
    // Implementation would analyze field distribution, query patterns, and write distribution
    // This is a simplified version focusing on query frequency
    const topFields = fieldStats.slice(0, 3).map(f => f.field);
    
    const recommendations = [];
    
    // Single field recommendations
    topFields.forEach(field => {
      recommendations.push({
        key: { [field]: 1 },
        reason: `High query frequency on ${field}`
      });
    });
    
    // Compound key recommendations (pairs of fields)
    if (topFields.length >= 2) {
      recommendations.push({
        key: { [topFields[0]]: 1, [topFields[1]]: 1 },
        reason: `Balanced distribution with most queried fields`
      });
    }
    
    return recommendations;
  }
}

// Execute the analysis
async function run() {
  const analyzer = new ShardKeyAnalyzer();
  await analyzer.analyzeLogFile();
  await analyzer.gatherCollectionStats();
  
  const recommendations = analyzer.generateShardKeyRecommendations();
  console.log(JSON.stringify(recommendations, null, 2));
}

run().catch(console.error);