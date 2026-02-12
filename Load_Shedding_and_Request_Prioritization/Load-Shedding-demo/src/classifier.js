export class PriorityClassifier {
  constructor() {
    this.rules = [
      { pattern: /^\/api\/checkout/, priority: 0, name: 'CRITICAL' },
      { pattern: /^\/api\/payment/, priority: 0, name: 'CRITICAL' },
      { pattern: /^\/api\/order/, priority: 1, name: 'IMPORTANT' },
      { pattern: /^\/api\/user/, priority: 1, name: 'IMPORTANT' },
      { pattern: /^\/api\/search/, priority: 2, name: 'NORMAL' },
      { pattern: /^\/api\/browse/, priority: 2, name: 'NORMAL' },
      { pattern: /^\/api\/analytics/, priority: 3, name: 'BACKGROUND' },
      { pattern: /^\/api\/recommendations/, priority: 3, name: 'BACKGROUND' }
    ];
  }

  classify(request) {
    const path = request.url;
    const userTier = request.headers['x-user-tier'] || 'free';
    
    // Find base priority from path
    let basePriority = 2; // default NORMAL
    let priorityName = 'NORMAL';
    
    for (const rule of this.rules) {
      if (rule.pattern.test(path)) {
        basePriority = rule.priority;
        priorityName = rule.name;
        break;
      }
    }
    
    // Adjust based on user tier
    if (userTier === 'premium' && basePriority > 0) {
      basePriority = Math.max(0, basePriority - 1);
    }
    
    return {
      priority: basePriority,
      name: priorityName,
      userTier,
      path
    };
  }
}
