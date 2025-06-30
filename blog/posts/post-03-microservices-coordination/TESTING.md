# Testing Chapter 3: Microservices Coordination Examples

This guide provides comprehensive testing scenarios for the microservices coordination patterns demonstrated in Chapter 3.

## 🚀 Quick Start Testing

```bash
# One-command setup with all services
curl -fsSL https://raw.githubusercontent.com/your-repo/chapter-3/setup.sh | bash

cd microservices-demo
docker-compose up -d

# Run quick test
./bin/test-registration
```

## 🧪 Test Scenarios

### 1. **Happy Path - Full Registration Success**

**Test**: All services respond successfully

```bash
# Create a new user registration
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "sarah@example.com",
    "name": "Sarah Chen",
    "plan": "pro",
    "phone": "+1-555-0123"
  }'

# Expected: Task completes with all steps successful
# Response includes task_id for monitoring
```

**What to verify:**
- User created in UserService (port 3001)
- Billing profile created in BillingService (port 3002)
- Preferences initialized in PreferencesService (port 3003)
- Welcome email queued in NotificationService (port 3004)
- All steps show "complete" status

### 2. **Service Timeout - Billing Service Slow**

**Test**: Billing service responds slowly, triggering timeout

```bash
# Simulate slow billing service
curl -X POST http://localhost:3002/admin/simulate/slowdown \
  -d '{"delay_seconds": 35}'

# Attempt registration
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "timeout.test@example.com",
    "name": "Timeout Test",
    "plan": "enterprise"
  }'

# Monitor the retry behavior
watch -n 1 curl http://localhost:3000/api/tasks/{TASK_ID}/status
```

**What to verify:**
- Initial billing step times out after 30 seconds
- Step enters retry with exponential backoff
- Other parallel steps (preferences) complete normally
- Eventually succeeds after billing service recovers

### 3. **Circuit Breaker - Service Completely Down**

**Test**: User service fails repeatedly, opening circuit breaker

```bash
# Take down user service
docker-compose stop user-service

# Attempt multiple registrations
for i in {1..6}; do
  curl -X POST http://localhost:3000/api/register \
    -H "Content-Type: application/json" \
    -d "{
      \"email\": \"breaker.test${i}@example.com\",
      \"name\": \"Breaker Test ${i}\"
    }"
  sleep 2
done

# Check circuit breaker status
curl http://localhost:3000/api/circuit-breakers/status
```

**What to verify:**
- First 5 attempts fail with connection errors
- 6th attempt fails immediately with "Circuit breaker OPEN"
- No additional calls made to user service
- Circuit breaker reopens after 60 seconds

### 4. **Idempotency - Duplicate Registration**

**Test**: Same user registered twice

```bash
# First registration
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "duplicate@example.com",
    "name": "Duplicate Test",
    "plan": "free"
  }'

# Wait for completion
sleep 5

# Exact same registration again
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "duplicate@example.com",
    "name": "Duplicate Test",
    "plan": "free"
  }'
```

**What to verify:**
- Second registration completes successfully
- User creation step shows "already_exists" status
- No duplicate billing profiles created
- Both tasks complete without errors

### 5. **Partial Failure Recovery - Preferences Service Error**

**Test**: Preferences service returns 500 error intermittently

```bash
# Configure preferences service to fail 50% of requests
curl -X POST http://localhost:3003/admin/simulate/errors \
  -d '{"error_rate": 0.5, "error_code": 500}'

# Register user
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "partial.failure@example.com",
    "name": "Partial Failure Test"
  }'

# Watch retries
watch -n 1 curl http://localhost:3000/api/tasks/{TASK_ID}/steps
```

**What to verify:**
- Preferences step fails initially
- Automatic retry with backoff
- Other steps continue independently
- Eventually succeeds within retry limit

### 6. **Rate Limiting - Notification Service**

**Test**: Notification service enforces rate limits

```bash
# Send 10 registrations rapidly
for i in {1..10}; do
  curl -X POST http://localhost:3000/api/register \
    -H "Content-Type: application/json" \
    -d "{
      \"email\": \"ratelimit${i}@example.com\",
      \"name\": \"Rate Limit Test ${i}\"
    }" &
done

# Monitor notification steps
curl http://localhost:3000/api/tasks?filter=recent | jq '.[] | select(.namespace=="user_management")'
```

**What to verify:**
- First few notification steps succeed
- Later ones get 429 Rate Limited response
- Steps respect Retry-After header
- Backoff prevents thundering herd

### 7. **Service Degradation - Free Plan Resilience**

**Test**: Billing service down but free users continue

```bash
# Stop billing service
docker-compose stop billing-service

# Register free user
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "free.degraded@example.com",
    "name": "Free User Test",
    "plan": "free"
  }'

# Register paid user (should fail)
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "paid.degraded@example.com",
    "name": "Paid User Test",
    "plan": "pro"
  }'
```

**What to verify:**
- Free user registration completes with degraded billing
- Paid user registration retries and eventually fails
- Graceful degradation for non-critical services

### 8. **Correlation Tracking - Distributed Debugging**

**Test**: Track request across all services

```bash
# Register with explicit correlation ID
CORRELATION_ID="debug_test_$(date +%s)"

curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"correlation@example.com\",
    \"name\": \"Correlation Test\",
    \"correlation_id\": \"${CORRELATION_ID}\"
  }"

# Search logs across all services
docker-compose logs | grep $CORRELATION_ID

# Check service dashboards
open http://localhost:3000/correlation-trace/$CORRELATION_ID
```

**What to verify:**
- Correlation ID appears in all service logs
- Can trace entire request flow
- Service timings are recorded
- Easy to identify failure points

### 9. **Parallel Execution - Performance Testing**

**Test**: Verify parallel steps execute simultaneously

```bash
# Add artificial delays to services
curl -X POST http://localhost:3002/admin/simulate/slowdown -d '{"delay_seconds": 5}'
curl -X POST http://localhost:3003/admin/simulate/slowdown -d '{"delay_seconds": 5}'

# Time registration
time curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "parallel@example.com",
    "name": "Parallel Test"
  }'
```

**What to verify:**
- Total time ~5-6 seconds (not 10+)
- Billing and preferences run in parallel
- Step timings show overlap
- Parallel savings recorded in annotations

### 10. **Peak Hours Simulation - Adaptive Timeouts**

**Test**: System adapts during high load

```bash
# Simulate peak hours
export SIMULATE_PEAK_HOURS=true

# Generate load
./bin/load-test --users 100 --duration 60s

# Monitor timeout adjustments
curl http://localhost:3000/api/metrics | grep timeout
```

**What to verify:**
- Timeouts increase during peak hours
- Backoff periods extended
- System remains stable under load
- Gradual recovery after peak

## 🔍 Monitoring and Debugging

### Check Service Health
```bash
# Overall system health
curl http://localhost:3000/api/health

# Individual service health
curl http://localhost:3001/health  # User Service
curl http://localhost:3002/health  # Billing Service
curl http://localhost:3003/health  # Preferences Service
curl http://localhost:3004/health  # Notification Service

# Circuit breaker status
curl http://localhost:3000/api/circuit-breakers/status
```

### View Distributed Traces
```bash
# If using Jaeger (with observability setup)
open http://localhost:16686

# Search by correlation ID or service name
```

### Database Inspection
```bash
# Check task states
docker-compose exec postgres psql -U tasker -c "
  SELECT t.id, t.status, t.created_at,
         COUNT(CASE WHEN ws.status = 'complete' THEN 1 END) as completed_steps,
         COUNT(ws.id) as total_steps
  FROM tasker_tasks t
  LEFT JOIN tasker_workflow_steps ws ON ws.task_id = t.id
  WHERE t.created_at > NOW() - INTERVAL '1 hour'
  GROUP BY t.id
  ORDER BY t.created_at DESC
  LIMIT 10;
"
```

## 🐛 Common Issues and Solutions

### "Circuit breaker is OPEN"
**Problem**: Service has failed too many times
**Solution**: 
- Wait for recovery timeout (60 seconds)
- Check service health: `docker-compose ps`
- Reset circuit breaker: `curl -X POST http://localhost:3000/api/circuit-breakers/reset`

### "Task stuck in pending"
**Problem**: No workers processing tasks
**Solution**:
- Check Sidekiq: `docker-compose logs sidekiq`
- Ensure Redis is running: `docker-compose ps redis`
- Restart workers: `docker-compose restart sidekiq`

### "All services timeout"
**Problem**: Network issues or resource constraints
**Solution**:
- Check Docker resources: `docker stats`
- Increase Docker memory allocation
- Check for port conflicts: `lsof -i :3001-3004`

### "Correlation ID not propagating"
**Problem**: Services not forwarding headers
**Solution**:
- Check service logs for X-Correlation-ID header
- Verify middleware is installed in each service
- Update service configuration

## 🎯 Performance Benchmarks

Expected performance under normal conditions:

| Operation | P50 | P95 | P99 |
|-----------|-----|-----|-----|
| Full Registration | 250ms | 800ms | 2s |
| User Creation | 50ms | 150ms | 300ms |
| Billing Setup | 100ms | 300ms | 500ms |
| Preferences Init | 30ms | 100ms | 200ms |
| Email Send | 200ms | 500ms | 1s |

## 🔧 Advanced Testing

### Chaos Engineering
```bash
# Random service failures
./bin/chaos-test --services all --failure-rate 0.1

# Network partition simulation
./bin/chaos-test --partition user-service,billing-service

# Resource exhaustion
./bin/chaos-test --memory-pressure notification-service
```

### Load Testing
```bash
# Gradual ramp-up
./bin/load-test --users 1..100 --ramp-time 60s --duration 300s

# Spike test
./bin/load-test --users 500 --ramp-time 0s --duration 60s

# Endurance test
./bin/load-test --users 50 --duration 3600s
```

---

Remember: The goal is to understand how Tasker handles the complexity of coordinating multiple services, not to test the services themselves. Focus on workflow resilience, retry strategies, and visibility into distributed operations.