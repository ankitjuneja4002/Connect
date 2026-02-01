# ⚡ Connect — Real-Time Chat Backend

> **Production-style chat API** — JWT auth, OTP signup, WebSocket live messaging, and an event-driven pipeline (Kafka → buffer → MongoDB). One command to run locally.

[![Java](https://img.shields.io/badge/Java-17-ED8B00?logo=openjdk&logoColor=white)](https://openjdk.org/)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3.5-6DB33F?logo=springboot&logoColor=white)](https://spring.io/projects/spring-boot)
[![MongoDB](https://img.shields.io/badge/MongoDB-47A248?logo=mongodb&logoColor=white)](https://www.mongodb.com/)
[![Redis](https://img.shields.io/badge/Redis-DC382D?logo=redis&logoColor=white)](https://redis.io/)
[![Kafka](https://img.shields.io/badge/Apache%20Kafka-231F20?logo=apachekafka&logoColor=white)](https://kafka.apache.org/)

---

## 🎯 What is this?

**Connect** is the backend for a real-time chat app: REST for **auth** (signup → OTP → login) and **rooms** (create, list, delete), and **WebSocket (STOMP)** for live chat. Messages flow through **Kafka** into an in-memory buffer and are written in batches to **MongoDB**. **Redis** caches OTPs and optional user cache. Built as a **monolithic** Spring Boot app so you can run and demo it with a single script.

Perfect for **portfolio**, **interviews**, or as a **reference** for Spring Boot + event-driven + real-time APIs.

---

## ✨ Features

| Area | What it does |
|------|----------------|
| **🔐 Auth** | Signup with email → OTP (cached in Redis, 5 min) → verify → login → JWT (1h). Demo mode when email isn’t configured. |
| **🏠 Rooms** | Create room (creator = admin), list all, delete (admin only). REST + JWT. |
| **💬 Real-time chat** | Connect via WebSocket (JWT), join room, send message. Message → Kafka → buffer (batch 10) → MongoDB. Live delivery over STOMP topics. |
| **📄 Demo UI** | Single-page app in `demo/` to hit every endpoint: health, auth, rooms, **chat** (WebSocket send/receive). |

---

## 🛠 Tech stack

| Layer | Tech |
|-------|------|
| **Language** | Java 17 |
| **Framework** | Spring Boot 3 |
| **Security** | Spring Security, JWT, BCrypt |
| **Real-time** | STOMP over WebSocket (SockJS) |
| **Messaging** | Apache Kafka |
| **Cache** | Redis |
| **Database** | MongoDB |

---

## 🏗 Architecture (high level)

REST + WebSocket → **Services** → **Repositories (MongoDB)**. Chat: **Kafka** topic `chat` → consumer → **in-memory buffer** (batch size 10) → **MongoDB** `messages`. **Redis**: OTP cache (5 min), optional `@Cacheable` (e.g. user list). **JWT** for stateless auth on REST and WebSocket.

![Connect Architecture](https://raw.githubusercontent.com/AdityaByte/Connect-Frontend/main/public/connect-architecture.png)

---

## 🚀 Quick start

**Prerequisites:** Java 17+, Docker (for MongoDB, Redis, Kafka).

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
./run-local.sh
```

Backend: **http://localhost:8080**. Demo UI: `cd demo && ./start-demo-server.sh` → **http://localhost:8000**.  
Full setup and env vars: [SETUP.md](SETUP.md).

---

## 📁 Repo at a glance

| Path | Purpose |
|------|---------|
| `src/main/java/com/connect/` | Controllers, services, repos, config, Kafka, buffer |
| `demo/` | Single-page demo UI + `start-demo-server.sh` |
| `run-local.sh` | Starts Docker (MongoDB, Redis, Kafka) + Spring Boot |
| `SETUP.md` | Setup and troubleshooting |

---

*Star ⭐ the repo if you find it useful.*
