const TenantMiddleware = (dbManager) => {
    return async (req, res, next) => {
        // Extract tenant ID from header, query param, or subdomain
        const tenantId = req.headers['x-tenant-id'] || 
                        req.query.tenant_id ||
                        req.body.tenant_id;
        
        if (tenantId) {
            req.tenantId = tenantId;
            
            // Store tenant context in request for logging
            req.tenantContext = {
                id: tenantId,
                timestamp: new Date().toISOString()
            };
        } else {
            // Default to first tenant for demo purposes
            req.tenantId = '11111111-1111-1111-1111-111111111111';
            req.tenantContext = {
                id: req.tenantId,
                timestamp: new Date().toISOString(),
                default: true
            };
        }
        
        next();
    };
};

module.exports = { TenantMiddleware };
