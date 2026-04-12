# Rate Limiter

A system design project exploring rate limiting algorithms and implementation strategies.

## Table of Contents
- [Overview](#overview)
- [Benefits](#benefits)
- [Implementation Approach](#implementation-approach)
- [Placement & Middleware](#placement--middleware)
- [Algorithms](#algorithms)
- [High-Level Architecture](#high-level-architecture)
- [Detailed Design](#detailed-design)
- [Distributed Environment Considerations](#distributed-environment-considerations)
- [Performance Optimization](#performance-optimization)
- [Monitoring](#monitoring)

## Overview

A rate limiter controls the number of client requests allowed within a specified period. Once the request count exceeds the defined threshold, excess calls are blocked.

**Examples:**
- Limit 2 posts per second per user
- Limit 10 account creations per day from same IP
- Limit 100 API calls per hour per client

## Benefits

- **Prevent Resource Starvation** — Ensures all users get fair access to resources
- **Reduce Cost** — Limits usage of expensive 3rd-party APIs and reduces unnecessary processing
- **Reduce Server Load** — Protects backend systems from being overwhelmed by excessive requests

## Implementation Approach

### Server-side vs Client-side

**Server-side**
- Pros: Reliable & enforceable, harder to bypass
- Cons: Higher server overhead, network latency
- Use Case: Production systems, security-critical

**Client-side**
- Pros: Reduces unnecessary network traffic, faster feedback
- Cons: Easily bypassed, unreliable
- Use Case: UI feedback, user experience

**Recommended:** Server-side for enforcement + client-side for UX

### Key Requirements

- **User Feedback** — Show users when throttled (429 status code)
- **Low Latency** — Rate limiting check must have minimal performance impact

## Placement & Middleware

Rate limiter should be implemented as **middleware** in the request pipeline:
- Executed early in request processing
- Returns **HTTP 429 (Too Many Requests)** status code when limit exceeded
- Minimal overhead to avoid latency issues

## Algorithms

### 1. Token Bucket

**How it works:**
- A bucket holds tokens up to a fixed capacity
- Tokens are added at a constant refill rate (e.g., 10 tokens/second)
- Each incoming request consumes one token
- If tokens are available, the request is allowed and a token is removed
- If the bucket is empty, the request is rejected (HTTP 429)

**Parameters:**
- `bucket_capacity` — maximum burst size allowed
- `refill_rate` — tokens added per unit time

**Pros:**
- Allows burst traffic up to bucket capacity
- Simple token count to track per user/client
- Flexible: easy to tune burst vs sustained rate independently

**Cons:**
- Two parameters to tune (capacity + refill rate) adds operational complexity
- Burst at the token refill boundary can still cause spikes

**Use Case:** APIs that want to allow short bursts (e.g., a user sending 10 quick requests) while enforcing a sustained average rate

### 2. Leaking Bucket
**How it works:** Requests are added to a queue (bucket) and processed at a fixed rate. If bucket is full, new requests are rejected.

**Pros:** Smooth traffic flow, prevents burst
**Cons:** Less flexible for traffic spikes

### 3. Fixed Window Counter
**How it works:** Count requests in fixed time windows (e.g., per minute). Reset counter at window boundary.

**Pros:** Simple to implement
**Cons:** Vulnerable to burst at window boundaries, requests can spike near edges

### 4. Sliding Window Log
**How it works:** Maintain a log of request timestamps. For each request, remove old timestamps outside the window and check count.

**Pros:** Accurate, handles edge cases well
**Cons:** Memory intensive, slower performance

### 5. Sliding Window Counter
**How it works:** Combination of fixed window and sliding window. Uses weighted rolling count across two windows.

**Pros:** Accurate, memory efficient, good performance balance
**Cons:** Slightly more complex than fixed window

---

## High-Level Architecture

The core idea is to use a **shared counter stored in Redis** (not in-process memory) so that all rate limiter instances share a consistent view of request counts.

**Why not in-memory?**
- In-memory caches are local to a single server — they don't work across multiple rate limiter nodes
- Redis is fast, supports atomic operations, and is purpose-built for this use case

**Request flow:**
1. Client sends a request to the rate limiter middleware
2. Rate limiter fetches the counter from the corresponding Redis bucket
3. If the limit is **not** reached → request is forwarded to API servers
4. If the limit **is** reached → request is rejected with **HTTP 429**

**Key Redis commands used:**
- `INCR` — increments the counter for the client
- `EXPIRE` — sets a timeout so the counter resets automatically after the window

---

## Detailed Design

### Component Overview

```
Rules (disk) ──► Workers ──► Cache (rules)
                                  │
Client ──► Rate Limiter ──────────┤──► API Servers
          Middleware       Redis  │
                          Cache   └──► Queue (dropped requests)
                        (counters)
```

- **Rules** are stored on disk; workers periodically pull them into a local cache
- When a client request arrives, the rate limiter checks the **rules cache** and the **Redis counter cache**
- If the request is **not** rate limited → forwarded to API servers
- If the request **is** rate limited → HTTP 429 is returned to the client; the request may optionally be enqueued for later processing

### Rate Limiting Rules

Rules are defined in configuration files (e.g., YAML) and loaded by workers into the cache. Example from Lyft's configuration:

```yaml
domain: messaging
descriptors:
  - key: message_type
    value: marketing
    rate_limit:
      unit: day
      requests_per_unit: 5
```

This rule allows clients to send at most **5 marketing messages per day**. Rules are generally written by engineers and stored on disk; the system reads them from cache at request time.

### Exceeding the Rate Limit

When a request is rate limited, the API returns:
- **HTTP 429 Too Many Requests**

**Rate Limiter Response Headers** — inform the client of their quota status:

| Header | Description |
|---|---|
| `X-Ratelimit-Remaining` | Number of allowed requests remaining in the current window |
| `X-Ratelimit-Limit` | Total number of requests the client can make per window |
| `X-Ratelimit-Retry-After` | Seconds to wait before making another request without being throttled |

---

## Distributed Environment Considerations

### Race Condition

In a distributed environment, a race condition can occur when multiple threads/servers read and write the counter concurrently.

**Example:**
- Counter value in Redis is **3**
- Two requests concurrently read the counter value as **3**
- Both increment to **4** and write back
- Correct value should be **5**, but both threads believe the counter is **4**

**Solutions:**
- **Locks** — most obvious fix, but significantly slows down the system
- **Lua scripts** — atomic scripts executed by Redis, preventing interleaving
- **Redis sorted sets** — use timestamps as scores; sliding window log implemented atomically in Redis

Lua scripts and sorted sets are the preferred approaches as they avoid the performance penalty of distributed locks.

### Synchronization Issue

When multiple rate limiter servers are deployed, they must share state. Without synchronization:
- Client 1 may send requests to Rate Limiter 1
- Client 2 may send requests to Rate Limiter 2
- If a client switches servers (stateless web tier), Rate Limiter 1 has no data about Client 2's requests

**Poor solution:** Sticky sessions — routes a client always to the same rate limiter. Not scalable or flexible.

**Recommended solution:** Use a **centralized data store (Redis)** shared by all rate limiter instances. All nodes read/write counters from the same Redis cluster, ensuring consistent state across the system.

---

## Performance Optimization

Two areas to focus on:

1. **Multi-data center setup** — For globally distributed systems, latency is a concern when the rate limiter is far from users. Setup multiple data centers (e.g., Cloudflare's 194+ edge servers) and route traffic to the closest rate limiter node.

2. **Eventual consistency for synchronization** — Use an eventual consistency model when synchronizing counter data between rate limiter nodes. If strict consistency isn't required across data centers, allow slight divergence and sync asynchronously to avoid latency penalties.

---

## Monitoring

After deployment, it's important to verify the rate limiter is working effectively. Key things to monitor:

- **The rate limiting algorithm is effective** — valid requests are not being dropped, and abusive traffic is being throttled correctly
- **The rate limiting rules are effective** — rules are neither too strict (dropping legitimate traffic) nor too loose (allowing abuse)

**Adjustment scenarios:**
- If rules are too **strict** → many valid requests are dropped; relax the threshold
- If there is a **sudden spike** in traffic (e.g., flash sale) → the current algorithm may drop too many requests; consider switching to a more burst-friendly algorithm like **Token Bucket**

Monitoring dashboards should track: requests allowed vs. dropped, 429 response rate, and per-client usage against limits.

---

**Status:** Design phase — algorithms documented, ready for implementation planning