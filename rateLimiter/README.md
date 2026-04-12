# Rate Limiter

A system design project exploring rate limiting algorithms and implementation strategies.

## Table of Contents
- [Overview](#overview)
- [Benefits](#benefits)
- [Implementation Approach](#implementation-approach)
- [Placement & Middleware](#placement--middleware)
- [Algorithms](#algorithms)

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
**How it works:** Tokens are added to a bucket at a fixed rate. Each request consumes a token. If no tokens available, request is rejected.

**Pros:** Handles burst traffic, flexible
**Cons:** More complex implementation

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

**Status:** Design phase — algorithms documented, ready for implementation planning