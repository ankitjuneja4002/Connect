# Connect — Backend

Backend for **Connect**, a real-time chat application. REST APIs for auth and rooms; WebSocket (STOMP) for live messaging. Monolithic Spring Boot app with event-driven message pipeline.

## Tech Stack

**Java 17** · **Spring Boot 3** · **Spring Security & JWT** · **STOMP over WebSocket** · **Apache Kafka** · **Redis** · **MongoDB**

## Features

- **Auth** — Signup, OTP verification (email / demo mode), login, JWT.
- **Rooms** — Create, list, delete (admin-only); REST.
- **Real-time chat** — Join room, send message, history; WebSocket + Kafka → buffer → MongoDB.
- **Demo** — Single-page UI in `demo/` to exercise all endpoints.

## Architecture (high level)

REST + WebSocket entrypoints → Services → Repositories (MongoDB). Chat messages: published to Kafka → consumed into in-memory buffer → batched write to MongoDB. Redis for OTP cache. JWT for stateless auth.


## Quick Start

**Prerequisites:** Java 17+, Docker (for MongoDB, Redis, Kafka).

```bash
./run-local.sh
```

Backend runs at `http://localhost:8080`. For full setup and demo UI, see [SETUP.md](SETUP.md).
