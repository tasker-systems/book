# Configuration Operational Guide

> Auto-generated operational tuning guide. Do not edit manually.
>
> Regenerate with: `cargo make generate-config-guide`

This guide provides operational tuning advice for the most important Tasker
configuration parameters. For the complete parameter reference, see the
[Configuration Reference](config-reference-complete.md).

Tasker uses a context-based configuration architecture:

- **Common** — shared across all contexts (database, queues, resilience, caching)
- **Orchestration** — orchestration-specific (gRPC, web, event systems, DLQ, batch processing)
- **Worker** — worker-specific (event systems, FFI dispatch, circuit breakers)

---

## Common Configuration

## Operational Tuning Guide for Tasker Common Configuration

This guide provides tuning recommendations for the most critical parameters within the `CommonConfig` section of Tasker, a Rust-based workflow orchestration platform. Adjustments to these settings are crucial for optimizing performance and resilience in development, staging, and production environments.

### Key Parameters Overview

- **Database Connection Pooling**: Controls connection pool size.
- **Message Queue (PGMQ) Configuration**: Sets buffer sizes and concurrency limits.
- **Circuit Breakers**: Manages error tolerance and recovery mechanisms.
- **MPSC Channels Buffer Size**: Determines the buffer size for communication channels.

### Database Connection Pool Configuration

| Parameter | Description | Adjustment Guidance | Recommended Values |
|-------------------|---------------------------------------------------------|--------------------------------------------------------|--------------------|
| `database.pool_size` | Maximum number of database connections in pool. | Increase if high contention or slow queries are observed; decrease to conserve resources. | Dev/Test: 5-10, Staging: 20-30, Production: 50+ |
| `database.max_idle_connections` | Number of idle connections kept open. | Adjust based on workload stability and connection overhead. | Dev/Test: 2, Staging: 5, Production: 10 |

### Message Queue (PGMQ) Configuration

| Parameter | Description | Adjustment Guidance | Recommended Values |
|-------------------|---------------------------------------------------------|--------------------------------------------------------|--------------------|
| `queues.buffer_size` | Maximum queue buffer size in messages. | Increase to handle bursts; decrease if latency is critical. | Dev/Test: 50, Staging: 100, Production: 200-300 |
| `queues.max_concurrency` | Concurrent message processing limit. | Adjust based on available system resources and workload spikes. | Dev/Test: 2, Staging: 5, Production: 10 |

### Circuit Breakers Configuration

| Parameter | Description | Adjustment Guidance | Recommended Values |
|-------------------|---------------------------------------------------------|--------------------------------------------------------|--------------------|
| `circuit_breakers.max_failures` | Number of failures before circuit trips. | Increase for more resilient systems; decrease to quickly fail over. | Dev/Test: 2, Staging: 5, Production: 10-15 |
| `circuit_breakers.reset_timeout` | Time (ms) before circuit breaker resets. | Longer timeouts are more conservative and reduce false positives. | Dev/Test: 30s, Staging: 60s, Production: 120s |

### MPSC Channels Buffer Size Configuration

| Parameter | Description | Adjustment Guidance | Recommended Values |
|-------------------|---------------------------------------------------------|--------------------------------------------------------|--------------------|
| `mpsc_channels.buffer_size` | Number of messages buffer can hold. | Increase to handle high message throughput; decrease for faster message delivery. | Dev/Test: 10, Staging: 25, Production: 50-75 |

These settings should be adjusted based on observed system performance metrics and operational needs across different deployment environments. Proper monitoring of these parameters is essential for maintaining optimal task execution efficiency and reliability in Tasker.

---

## Orchestration Configuration

# Operational Tuning Guide for Tasker's Orchestration Configuration

This guide provides insights into key parameters of the Orchestration configuration in Tasker to optimize performance and resource utilization. Adjust these settings based on your deployment environment: development/test (small), staging (medium), or production (large).

| Parameter | Description | Adjustment Criteria | Small (dev/test) | Medium (staging) | Large (production) |
|----------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------|--------------------------|-------------------------|--------------------------|
| `shutdown_timeout_ms` | Maximum time to wait for orchestration subsystems to stop during graceful shutdown. | Increase if subsystems take longer to shut down | 30,000 ms (30 sec) | 60,000 ms (1 min) | 90,000 ms (1.5 min) |
| `grpc.bind_address` | IP address and port for gRPC server to listen on. | Not typically changed | 0.0.0.0:9090 | 0.0.0.0:9090 | 0.0.0.0:9090 |
| `grpc.tls_enabled` | Enables TLS for gRPC connections (use if security is required). | Enable in production | false | true | true |
| `grpc.keepalive_interval_seconds` | Interval between keep-alive pings to maintain HTTP/2 connection. | Increase for more stable, less chatty connections| 30 seconds | 60 seconds | 180 seconds (3 min) |
| `grpc.max_concurrent_streams` | Maximum number of concurrent gRPC streams per connection. | Increase with higher traffic | 200 | 500 | 1,000 |
| `grpc.enable_reflection` | Enables the gRPC reflection service for easier discovery and debugging (recommended for development). | Disable in production | true | false | false |

### Detailed Parameter Descriptions

#### shutdown_timeout_ms

- **What it controls:** Specifies the maximum time to wait during a graceful shutdown of orchestration subsystems before forceful termination.
- **Adjustment Criteria:**
- Increase if subsystems tend to take longer to shut down, particularly in large deployments with many active tasks or connections.
- Decrease if quick startup/shutdown is prioritized over thorough cleanup.
- **Recommended Values:**
- Small (dev/test): 30 seconds
- Medium (staging): 1 minute
- Large (production): 1.5 minutes

#### grpc.bind_address

- **What it controls:** IP address and port for the gRPC server to listen on.
- **Adjustment Criteria:** Typically set to `0.0.0.0` to bind to all available network interfaces, useful in cloud environments where external IPs are dynamic.

#### grpc.tls_enabled

- **What it controls:** Enables Transport Layer Security (TLS) for secure gRPC connections.
- **Adjustment Criteria:**
- Enable if the application is handling sensitive data or exposed publicly over untrusted networks.
- Disable only in internal testing environments where security risks are minimal.

#### grpc.keepalive_interval_seconds

- **What it controls:** Interval between keep-alive pings to maintain HTTP/2 connections, ensuring no idle timeouts occur.
- **Adjustment Criteria:**
- Increase for more stable, less chatty connections (useful across unreliable networks).
- Decrease in high-frequency environments where quick response times are critical.

#### grpc.max_concurrent_streams

- **What it controls:** The maximum number of concurrent gRPC streams allowed per connection.
- **Adjustment Criteria:**
- Increase if your application expects a high volume of concurrent operations or connections, but be mindful of resource constraints.

#### grpc.enable_reflection

- **What it controls:** Enables the gRPC reflection service for easier discovery and debugging.
- **Adjustment Criteria:**
- Enable during development to facilitate introspection and tool integration.
- Disable in production to minimize potential security risks.

By carefully tuning these parameters, you can optimize Tasker's performance and reliability across various deployment scenarios.

---

## Worker Configuration

## Operational Tuning Guide for Tasker Worker Configuration

The following guide provides instructions on tuning the key parameters of the `WorkerConfig` structure in the Tasker workflow orchestration platform. This section focuses on optimizing the performance and reliability of workers by adjusting critical settings.

### Key Parameters Overview

1. **Circuit Breakers (`circuit_breakers`)**
2. **Event Systems (`event_systems`)**
3. **MPSC Channels (`mpsc_channels`)**
4. **Orchestration Client (`orchestration_client`)** (optional)
5. **Web API Configuration (`web`)** (optional)
6. **gRPC API Configuration (`grpc`)** (optional)

### Circuit Breakers

The `circuit_breakers` configuration is crucial for managing worker stability by preventing overload and ensuring quick recovery from issues.

| Parameter | Description | Adjustment Guidance | Recommended Values |
|-----------|-------------|---------------------|--------------------|
| **failure_threshold** | Number of slow/failed sends before the circuit breaks. | Increase if frequent false positives; decrease to be more sensitive to failures. | Small: 5, Medium: 10, Large: 20 |
| **recovery_timeout_seconds** | Time (in seconds) for which a broken circuit stays open before attempting recovery. | Decrease to accelerate recovery time; increase to avoid premature reopening. | Small: 5, Medium: 10, Large: 15 |
| **success_threshold** | Number of successful fast sends required in the half-open state to close the circuit again. | Increase if false negatives are common; decrease for faster recovery attempts. | Small: 2, Medium: 3, Large: 4 |
| **slow_send_threshold_ms** | Latency above which a send is considered slow and contributes to breaking the circuit. | Decrease to be more sensitive to latency issues; increase to avoid unnecessary circuit breaks. | Small: 100, Medium: 200, Large: 300 |

### Event Systems

The `event_systems` configuration determines how workers handle event-driven operations.

| Parameter | Description | Adjustment Guidance | Recommended Values |
|-----------|-------------|---------------------|--------------------|
| **worker** | Configuration for the worker-specific event system. | Adjust based on specific needs of each deployment environment to ensure optimal event handling. | Small: Default, Medium: Customized, Large: Highly optimized |

### MPSC Channels

The `mpsc_channels` configuration is essential for managing message passing between different components.

| Parameter | Description | Adjustment Guidance | Recommended Values |
|-----------|-------------|---------------------|--------------------|
| **batch_size** | Number of messages to process in a single batch. | Increase or decrease based on performance tuning and resource availability. | Small: 10, Medium: 50, Large: 100 |
| **max_buffer_length** | Maximum length of the buffer queue before backpressure starts. | Adjust according to expected message volume and system capacity. | Small: 20, Medium: 100, Large: 300 |

### Orchestration Client

The `orchestration_client` configures how workers connect to the orchestration API.

| Parameter | Description | Adjustment Guidance | Recommended Values |
|-----------|-------------|---------------------|--------------------|
| **connection_timeout** | Maximum time to wait for a connection attempt before timing out. | Increase in environments with high network latency; decrease in highly responsive setups. | Small: 10s, Medium: 20s, Large: 30s |
| **retry_attempts** | Number of retry attempts upon initial failure to connect. | Adjust based on the reliability and availability of the orchestration service. | Small: 3, Medium: 5, Large: 7 |

### Web API Configuration

The `web` configuration sets parameters for the worker's web-based interface.

| Parameter | Description | Adjustment Guidance | Recommended Values |
|-----------|-------------|---------------------|--------------------|
| **listen_address** | IP address and port on which to listen. | Adjust based on deployment specifics such as network topology and security constraints. | Small: Localhost, Medium: Internal Network, Large: Public Internet |

### gRPC API Configuration

The `grpc` configuration is used for setting up the worker's gRPC-based interface.

| Parameter | Description | Adjustment Guidance | Recommended Values |
|-----------|-------------|---------------------|--------------------|
| **max_concurrent_streams** | Maximum number of concurrent streams allowed. | Adjust based on expected load and available system resources. | Small: 10, Medium: 50, Large: 200 |

### Conclusion

By fine-tuning these parameters, operators can significantly enhance the performance, reliability, and responsiveness of Tasker workers across different deployment environments. Careful monitoring and iterative adjustments are key to achieving optimal results.

---

> Operational guidance generated with Ollama (`qwen2.5:14b`). Set `SKIP_LLM=true` for deterministic output.

---

*Generated by `generate-config-guide.sh` from tasker-core configuration source*
