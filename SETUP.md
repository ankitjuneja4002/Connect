# How to Setup

**Prerequisites:** Java 17+, Docker Desktop (running), Maven (wrapper included).

**Quick start:**

```bash
./run-local.sh
```

This creates `.env` if missing, starts MongoDB/Redis/Kafka via Docker, waits for them, then runs the Spring Boot app. When you see `Started ConnectApplication`, the backend is at `http://localhost:8080`.

**Manual:** Run `docker compose up -d`, set env vars (see `.env.example` or `.env`), then `./mvnw spring-boot:run`.

**Demo UI:** From project root, `cd demo && ./start-demo-server.sh`, then open `http://localhost:8000/index.html`.

**Troubleshooting:** Ensure Docker Desktop is running; if ports 27017/6379/9092 are in use, stop conflicting services or adjust `docker-compose.yml` and `.env`.
