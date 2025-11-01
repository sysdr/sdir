# IAM System Design Demo
**Issue #151: Identity and Access Management**

## Architecture Overview

This demo implements a production-like IAM system with:

- **OAuth 2.0 Authorization Code Flow**: Secure third-party authorization
- **Hybrid JWT Strategy**: Short-lived JWTs (5 min) with Redis-based revocation
- **RBAC Foundation**: Role-based access control with Admin/User/Viewer roles
- **ABAC Example**: Attribute-based policy (time-of-day restrictions)
- **Refresh Token Pattern**: Long-lived refresh tokens (24 hours) for token renewal
- **Session Management**: Redis-backed sessions for immediate revocation
- **Zero Trust Principles**: Authentication and authorization at every service boundary

### Components

1. **Auth Server** (Port 3001): Handles authentication, OAuth flows, token issuance
2. **Resource Server** (Port 3002): Protected API requiring valid JWT tokens
3. **Dashboard** (Port 3000): Web-based dashboard for monitoring system health and metrics
4. **PostgreSQL**: Stores users, roles, permissions, policies
5. **Redis**: Session store and token revocation list

## Quick Start
```bash
# Start all services
docker-compose up -d

# Wait for services to be healthy (30-60 seconds)
docker-compose ps

# Check service health
curl http://localhost:3001/health
curl http://localhost:3002/health

# Access web dashboard
# Open in browser: http://localhost:3000
```

## Demo Flow: Complete OAuth 2.0 Authorization Code Flow

### Step 1: Request Authorization Code
```bash
curl -X GET "http://localhost:3001/oauth/authorize?client_id=demo-client&redirect_uri=http://localhost:8080/callback&response_type=code&scope=read&state=xyz123"
```

**Response**: You'll get a JSON with `redirect_to` URL containing the authorization code.
```json
{
  "message": "Authorization successful",
  "redirect_to": "http://localhost:8080/callback?code=<AUTH_CODE>&state=xyz123",
  "note": "In browser, user would be redirected to this URL"
}
```

Extract the `code` parameter from the redirect URL.

### Step 2: Exchange Code for Tokens
```bash
# Replace <AUTH_CODE> with the code from step 1
curl -X POST http://localhost:3001/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code" \
  -d "code=<AUTH_CODE>" \
  -d "client_id=demo-client" \
  -d "client_secret=demo-secret" \
  -d "redirect_uri=http://localhost:8080/callback"
```

**Response**:
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 300,
  "refresh_token": "a1b2c3d4e5f6...",
  "scope": "read"
}
```

Save the `access_token` and `refresh_token` for next steps.

### Step 3: Access Protected Resource
```bash
# Replace <ACCESS_TOKEN> with token from step 2
curl -X GET http://localhost:3002/api/documents \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

**Success Response**:
```json
{
  "message": "Document list",
  "documents": [
    {"id": 1, "title": "Q4 Report", "owner": "alice"},
    {"id": 2, "title": "Architecture Design", "owner": "bob"}
  ],
  "accessed_by": "alice",
  "roles": ["user"]
}
```

### Step 4: Demonstrate Token Revocation
```bash
# Revoke the access token
curl -X POST http://localhost:3001/oauth/revoke \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "token=<ACCESS_TOKEN>" \
  -d "token_type_hint=access_token"
```

**Response**:
```json
{
  "message": "Token revoked successfully"
}
```

Now try to access the protected resource again:
```bash
curl -X GET http://localhost:3002/api/documents \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

**Error Response** (immediate revocation works!):
```json
{
  "error": "Token has been revoked"
}
```

### Step 5: Refresh Token Flow
```bash
# Use refresh token to get new access token
curl -X POST http://localhost:3001/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "refresh_token=<REFRESH_TOKEN>" \
  -d "client_id=demo-client" \
  -d "client_secret=demo-secret"
```

**Response**:
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 300
}
```

### Step 6: Test Permission Boundaries (RBAC)

Alice (role: user) can read and write documents but cannot delete:
```bash
# This works - user has write permission
curl -X POST http://localhost:3002/api/documents \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title": "New Document"}'

# This fails - user lacks delete permission
curl -X DELETE http://localhost:3002/api/documents/1 \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

**Error Response**:
```json
{
  "error": "Insufficient permissions",
  "required": "delete:documents",
  "has": ["read:documents", "write:documents"]
}
```

### Step 7: Test ABAC Policy Evaluation
```bash
curl -X POST http://localhost:3001/policy/evaluate \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": 2,
    "resource_type": "documents",
    "action": "read",
    "context": {
      "current_time": "2025-11-01T14:00:00Z"
    }
  }'
```

**Response** (during business hours):
```json
{
  "allowed": true,
  "evaluated_policies": 1
}
```

### Step 8: Test Public Endpoint (No Auth)
```bash
curl http://localhost:3002/api/public/info
```

This demonstrates that not all endpoints require authentication.

## Learning Outcomes

### Authentication vs Authorization Patterns
- **Observed**: Auth server issues tokens (authentication), resource server validates tokens and checks permissions (authorization)
- **Key Insight**: Separation allows independent scaling and security policies

### OAuth 2.0 Authorization Code Flow
- **Observed**: Three-step flow (authorize → code → token) with redirect URI validation and state parameter
- **Key Insight**: Authorization code prevents token leakage via browser redirects; server-side token exchange keeps client secret secure

### JWT Strategy + Revocation
- **Observed**: Short-lived JWTs (5 min) reduce revocation urgency; Redis revocation list handles immediate invalidation
- **Key Insight**: Hybrid pattern balances performance (stateless JWT) with control (server-side revocation)

### RBAC → ABAC Migration Pattern
- **Observed**: RBAC handles 90% of use cases with simple role checks; ABAC policies add context-aware rules
- **Key Insight**: Start with RBAC for simplicity, add ABAC selectively for complex requirements

### Zero Trust Architecture
- **Observed**: Every API call requires token validation; resource server doesn't trust tokens without verification
- **Key Insight**: No implicit trust based on network location; authenticate and authorize at every boundary

## System Design Interview Talking Points

### 1. **Token Lifespan Trade-offs**
- Short JWTs reduce revocation window but increase token refresh frequency
- Long JWTs improve performance but complicate immediate revocation
- **Production Pattern**: 5-15 min access tokens, 7-30 day refresh tokens

### 2. **Revocation at Scale**
- Redis revocation list works for millions of tokens (O(1) lookups)
- For 100M+ users, consider bloom filters or distributed revocation checks
- **Key Question**: What's the SLA for revocation? (immediate vs. eventual)

### 3. **Session Store Design**
- Redis provides single-digit millisecond latency for session checks
- For global systems, consider geo-distributed Redis clusters with replication
- **Failure Mode**: If Redis fails, fall back to stateless JWT validation (degraded security vs. availability)

### 4. **Authorization Caching**
- Cache permission lookups to avoid database hits on every request
- Balance cache TTL with permission update latency requirements
- **Pattern**: 1-5 minute cache for permissions, invalidate on role changes

### 5. **Policy Propagation**
- Centralized policy management with eventually consistent distribution
- For critical systems, use synchronous policy updates with increased latency
- **Trade-off**: Consistency vs. performance at the policy decision point

### 6. **OAuth Scaling Patterns**
- Authorization code table grows linearly with authorization requests
- Cleanup strategy: Delete expired codes via background job (shown in schema with TTL index)
- **Production**: Partition auth codes by creation time for efficient cleanup

### 7. **Audit Log Strategy**
- Every access decision should be logged for security analysis
- Separate hot path (fast writes) from analytics (batch processing)
- **Pattern**: Async log writes to avoid blocking authorization decisions

### 8. **Token Introspection Cost**
- Resource servers can validate JWTs locally (fast) or call auth server (authoritative)
- Hybrid: Local validation with periodic introspection for high-security operations
- **Decision Point**: Trust JWTs for reads, introspect for writes/deletes

## Cleanup
```bash
# Stop and remove all containers and volumes
docker-compose down -v

# Remove images (optional)
docker-compose down -v --rmi all
```

## Production Considerations

1. **Use HTTPS**: All token exchanges must use TLS in production
2. **Rotate JWT Secrets**: Implement key rotation strategy with multiple active keys
3. **Rate Limiting**: Add rate limits to prevent brute force attacks on token endpoints
4. **PKCE for Public Clients**: Use Proof Key for Code Exchange for mobile/SPA apps
5. **Audit Logging**: Enable comprehensive audit logs for all authorization decisions
6. **Token Encryption**: Consider encrypting tokens at rest in refresh token table
7. **Secure Client Secrets**: Use secrets management (AWS Secrets Manager, HashiCorp Vault)
8. **MFA Support**: Add multi-factor authentication for sensitive operations

## Testing Different Users

The demo includes three users with different roles:

- **admin** (role: admin): Full access to all resources
- **alice** (role: user): Can read and write documents
- **bob** (role: viewer): Can only read documents

Password for all users: `password123`

## Architecture Diagram References

See the SVG diagrams for visual representation:
- `oauth2-authz-code-flow.svg`: Complete OAuth 2.0 flow
- `zero-trust-architecture.svg`: Zero Trust principles
- `jwt-hybrid-revocation.svg`: Token lifecycle and revocation

## Next Steps

1. Implement PKCE extension for mobile clients
2. Add mTLS between services for Zero Trust architecture
3. Implement attribute-based policies with more complex conditions
4. Add OpenID Connect layer for identity federation
5. Implement token rotation strategy with overlapping validity periods

---

**System Design Interview Prep**: This demo covers key IAM patterns asked in FAANG interviews including token management, authorization scaling, revocation strategies, and security trade-offs.
