// Event types
const EventTypes = {
  ACCOUNT_CREATED: 'ACCOUNT_CREATED',
  MONEY_DEPOSITED: 'MONEY_DEPOSITED',
  MONEY_WITHDRAWN: 'MONEY_WITHDRAWN',
  MONEY_TRANSFERRED: 'MONEY_TRANSFERRED'
};

// Event factory
function createEvent(aggregateId, type, data) {
  return {
    aggregateId,
    type,
    data,
    timestamp: new Date().toISOString(),
    eventId: `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
  };
}

module.exports = { EventTypes, createEvent };
