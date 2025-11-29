import crypto from 'crypto';

export class Block {
  constructor(index, timestamp, transactions, previousHash, validator) {
    this.index = index;
    this.timestamp = timestamp;
    this.transactions = transactions;
    this.previousHash = previousHash;
    this.validator = validator;
    this.hash = this.calculateHash();
    this.stateRoot = this.calculateStateRoot();
  }

  calculateHash() {
    const data = this.index + this.timestamp + JSON.stringify(this.transactions) + 
                  this.previousHash + this.validator;
    return crypto.createHash('sha256').update(data).digest('hex');
  }

  calculateStateRoot() {
    const stateData = JSON.stringify(this.transactions.map(tx => ({
      from: tx.from,
      to: tx.to,
      amount: tx.amount
    })));
    return crypto.createHash('sha256').update(stateData).digest('hex').substring(0, 16);
  }
}

export class Transaction {
  constructor(from, to, amount, gasPrice, timestamp) {
    this.id = crypto.randomBytes(8).toString('hex');
    this.from = from;
    this.to = to;
    this.amount = amount;
    this.gasPrice = gasPrice;
    this.timestamp = timestamp || Date.now();
    this.status = 'pending';
  }

  calculateHash() {
    const data = this.from + this.to + this.amount + this.gasPrice + this.timestamp;
    return crypto.createHash('sha256').update(data).digest('hex');
  }
}

export class Mempool {
  constructor() {
    this.transactions = [];
    this.maxSize = 1000;
  }

  addTransaction(transaction) {
    if (this.transactions.length >= this.maxSize) {
      // Remove lowest gas price transaction
      this.transactions.sort((a, b) => b.gasPrice - a.gasPrice);
      this.transactions = this.transactions.slice(0, this.maxSize - 1);
    }
    
    this.transactions.push(transaction);
    // Sort by gas price (descending)
    this.transactions.sort((a, b) => b.gasPrice - a.gasPrice);
    
    return true;
  }

  getTopTransactions(count) {
    return this.transactions.slice(0, Math.min(count, this.transactions.length));
  }

  removeTransactions(txIds) {
    this.transactions = this.transactions.filter(tx => !txIds.includes(tx.id));
  }

  getSize() {
    return this.transactions.length;
  }

  getTransactions() {
    return this.transactions;
  }
}

export class Blockchain {
  constructor(nodeId, validatorStake) {
    this.nodeId = nodeId;
    this.chain = [this.createGenesisBlock()];
    this.mempool = new Mempool();
    this.validatorStake = validatorStake;
    this.accounts = this.initializeAccounts();
    this.difficulty = 2;
    this.blockTime = 3000; // 3 seconds
    this.lastBlockTime = Date.now();
  }

  initializeAccounts() {
    const accounts = {};
    const users = ['Alice', 'Bob', 'Charlie', 'Dave', 'Eve'];
    users.forEach(user => {
      accounts[user] = { balance: 1000, nonce: 0 };
    });
    return accounts;
  }

  createGenesisBlock() {
    return new Block(0, Date.now(), [], '0', 'genesis');
  }

  getLatestBlock() {
    return this.chain[this.chain.length - 1];
  }

  addTransaction(transaction) {
    // Validate transaction
    const sender = this.accounts[transaction.from];
    if (!sender || sender.balance < transaction.amount) {
      return { success: false, error: 'Insufficient balance' };
    }

    this.mempool.addTransaction(transaction);
    return { success: true, txId: transaction.id };
  }

  canProposeBlock() {
    const timeSinceLastBlock = Date.now() - this.lastBlockTime;
    return timeSinceLastBlock >= this.blockTime;
  }

  selectValidator() {
    // Simple PoS: probability proportional to stake
    return this.nodeId;
  }

  async createBlock() {
    if (!this.canProposeBlock()) {
      return null;
    }

    const validator = this.selectValidator();
    const transactions = this.mempool.getTopTransactions(20);
    
    if (transactions.length === 0) {
      return null;
    }

    const newBlock = new Block(
      this.chain.length,
      Date.now(),
      transactions,
      this.getLatestBlock().hash,
      validator
    );

    return newBlock;
  }

  validateBlock(block) {
    const latestBlock = this.getLatestBlock();
    
    if (block.previousHash !== latestBlock.hash) {
      return { valid: false, error: 'Invalid previous hash' };
    }

    if (block.index !== latestBlock.index + 1) {
      return { valid: false, error: 'Invalid block index' };
    }

    if (block.hash !== block.calculateHash()) {
      return { valid: false, error: 'Invalid block hash' };
    }

    return { valid: true };
  }

  addBlock(block) {
    const validation = this.validateBlock(block);
    
    if (!validation.valid) {
      return { success: false, error: validation.error };
    }

    // Update state
    block.transactions.forEach(tx => {
      if (this.accounts[tx.from] && this.accounts[tx.to]) {
        this.accounts[tx.from].balance -= tx.amount;
        this.accounts[tx.to].balance += tx.amount;
        tx.status = 'confirmed';
      }
    });

    this.chain.push(block);
    this.mempool.removeTransactions(block.transactions.map(tx => tx.id));
    this.lastBlockTime = Date.now();

    return { success: true, block };
  }

  getChainLength() {
    return this.chain.length;
  }

  getStats() {
    return {
      nodeId: this.nodeId,
      chainLength: this.chain.length,
      mempoolSize: this.mempool.getSize(),
      validatorStake: this.validatorStake,
      latestBlock: this.getLatestBlock(),
      accounts: this.accounts
    };
  }
}
