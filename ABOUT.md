# Connect Backend — Full Project Deep Dive (Interview Prep)

This document explains **every part** of the project so you can answer any interview question. Read it like a story: what happens when a user signs up, logs in, creates a room, or sends a chat message.

---

## 1. What Is This Project (One Sentence)

A **real-time chat backend**: REST APIs for auth and room CRUD, WebSocket (STOMP) for live chat. Messages go through Kafka → in-memory buffer → batch write to MongoDB. Redis stores OTP and temporary user data during signup.

---

## 2. Full Journey: What Happens End-to-End

### 2.1 User Signs Up (Step-by-Step)

1. **Client** sends `POST /auth/signup` with body: `{ username, email, password, role }`.
2. **AuthController.signupHandler()** receives it and calls **AuthService.signupHandler(user)**.
3. **AuthService**:
   - Checks if **email** or **username** already exists in **MongoDB** via **UserRepository.findByEmail()** and **findByUsername()**. If yes → throws **DuplicateResourceException** (handled by **GlobalExceptionHandler** → 400).
   - Calls **OTPService.generateOTPForUser(user.getEmail())**:
     - Generates a **4-digit OTP** (1000–9999) using **SecureRandom**.
     - Builds **OtpDTO** with `otp` and `email`.
     - Calls **RedisService.cacheOTPWithTTL(otpDTO)** → Redis key **`otp:<email>`**, value = OtpDTO JSON, **TTL = 5 minutes**.
     - Returns the OTP string.
   - Calls **EmailService.sendEmail(to, subject, body)**. Body is from **EmailUtil.getBody()** (template with username and OTP). If email is not configured or DEMO_MODE=true, **EmailService** does **not** send; it just logs. OTP is already in Redis.
   - Calls **RedisService.cacheUserWithTTL(user)** → Redis key **`user:<email>`**, value = User object (plaintext password at this point). **No TTL** on user cache (stays until we remove it after createUser).
4. **Controller** returns `200` with `"OTP sent to your email"`.

**Summary:** Signup = validate uniqueness in MongoDB → generate OTP → store OTP in Redis (5 min) → (optionally) send email → store User in Redis for later verification.

---

### 2.2 User Verifies OTP and Gets Created in DB

1. **Client** sends `POST /auth/signup/verifyOTP` with body: `{ email, otp }`.
2. **AuthController.verifyOTPHandler()** → **AuthService.createUser(otp, email)**.
3. **AuthService.createUser()**:
   - **OTPService.verifyOTP(email, otp)**:
     - **RedisService.getOTP(email)** → reads key **`otp:<email>`** from Redis. If null → OTP expired, return false.
     - Compares email and otp with stored OtpDTO. If mismatch → return false.
     - Returns true if valid.
   - If invalid → throws `"Invalid OTP"`.
   - **RedisService.removeOTP(email)** → deletes **`otp:<email>`** from Redis.
   - **RedisService.getUser(email)** → gets User from **`user:<email>`** in Redis. If null → throws **TimeoutException** ("User not found in the cache").
   - Encodes password with **BCryptPasswordEncoder**, sets **UserRole.USER**, then **UserRepository.createUser()** → **MongoTemplate.insert(user)** into MongoDB collection **`users`**.
   - **RedisService.removeUser(email)** → deletes **`user:<email>`** from Redis.
4. Returns created User; controller returns `201` with "User created successfully".

**Summary:** Verify OTP from Redis → delete OTP → get User from Redis → encode password → save to MongoDB → delete User from Redis.

---

### 2.3 Resend OTP

1. **Client** sends `GET /auth/signup/resendOTP?email=...`.
2. **AuthService.resendOTP(email)**:
   - **RedisService.getUser(email)** → user must exist in Redis (from signup). If not → "Email doesn't exists, Bad Request!".
   - **RedisService.removeOTP(email)** → delete old OTP.
   - **OTPService.generateOTPForUser(email)** → new OTP, stored in Redis again (5 min).
   - **EmailService.sendEmail(...)** again (or skip in demo).
3. Returns "OTP sent successfully".

---

### 2.4 User Logs In

1. **Client** sends `POST /auth/login` with body: `{ email, password }`.
2. **AuthController.loginHandler()** → **AuthService.loginHandler(loginUser)**.
3. **AuthService**:
   - **AuthenticationManager.authenticate(UsernamePasswordAuthenticationToken(email, password))**:
     - Spring Security uses **CustomUserDetailsImpl.loadUserByUsername(email)** → **UserRepository.findByEmail(email)** → loads User from **MongoDB**.
     - Builds **CustomUserDetails** (implements UserDetails) from User.
     - Compares password with **PasswordEncoder.matches()** (BCrypt). If wrong → "Bad Credentials".
   - **JwtUtil.generateToken(username, email)**:
     - Builds JWT with subject=username, claim email, issuedAt, expiration (1 hour = 1000*60*60 ms).
     - Signs with **HS256** and **jwt.secret.key** from config.
     - Returns compact token string.
   - **UserRepository.updateUserStatus(username, UserStatus.ACTIVE)** is called **@Async** (runs on **asyncTaskExecutor** thread pool from **AsyncConfiguration**): updates user's `status` to ACTIVE in MongoDB.
   - Returns `Map.of("token", token, "expiresAt", expiry)`.
4. Controller returns this map to client. Client stores token and sends it as `Authorization: Bearer <token>` on protected calls.

**Summary:** Login = load user from MongoDB by email → verify password (BCrypt) → generate JWT (1h) → async set status ACTIVE → return token.

---

### 2.5 Create Room (REST)

1. **Client** sends `POST /room/create` with header `Authorization: Bearer <token>` and body `{ roomName, roomDescription }`.
2. **ChatRoomController.createRoom()**:
   - Reads token from header (substring(7) to skip "Bearer ").
   - **JwtTokenService.extractUsername(token)** → **JwtUtil.extractClaims(token)** → parse JWT, get **subject** (username). If invalid/expired → null.
   - If username null → 401 "Invalid Token or Room Creation Failed".
   - **RoomService.addNewRoom(room, username)**:
     - **UserRepository.findByUsername(username)** → get User from MongoDB.
     - Sets **room.setAdmin(user)** (the creator is admin).
     - **RoomRepository.addRoom(room)** → **MongoTemplate.insert(room)** into collection **`rooms`**. Room has **roomId** (auto-generated by MongoDB as _id), roomName, roomDescription, timeStamp, admin (DBRef to User).
   - Returns 200 "Room created successfully".
3. **Note:** SecurityConfig has **anyRequest().permitAll()**, so the server does **not** reject unauthenticated requests at the filter level. Protection is only **inside** the controller via manual token extraction. So in theory anyone could call /room/create without a token and get null username → 401; but there is no JWT filter blocking before the controller.

---

### 2.6 Get All Rooms

1. **Client** sends `GET /room/getall` (no auth required in code).
2. **ChatRoomController.fetchRooms()** → **RoomService.getRooms()** → **RoomRepository.getRooms()** → **MongoTemplate.find(query, Room.class)** with a query that includes roomId, roomName, date, admin, roomDescription.
3. Returns list of **RoomDTO** (roomId, roomName, etc.).

---

### 2.7 Delete Room (Admin Only)

1. **Client** sends `DELETE /room/delete/{roomId}` with `Authorization: Bearer <token>`.
2. **ChatRoomController.deleteRoom()**:
   - Extracts username from JWT (same as create).
   - **RoomService.deleteRoom(roomId, username)**:
     - **UserRepository.findByUsername(username)** → get User (need **user.getId()** = ObjectId).
     - **RoomRepository.findRoomByIDAndAdminUserId(roomId, user.getId())** → query: roomId **and** `admin.$id` = user's ObjectId. So only the room where this user is admin.
     - If found → **RoomRepository.deleteRoomById(roomId)** → **MongoTemplate.remove(query, Room.class)**. Returns true.
     - If not found (wrong room or not admin) → false.
   - If false → 403 "Room not found or you are not the admin of this room". If true → 200 "Room deleted successfully".

---

### 2.8 WebSocket: Connect and Greet

1. **Client** connects to **http://localhost:8080/ws** using **SockJS** and **STOMP**. On CONNECT frame it sends header **Authorization: Bearer <token>**.
2. **WebSocketConfig** has a **ChannelInterceptor** on the client inbound channel. On **StompCommand.CONNECT**:
   - Reads **Authorization** header, strips "Bearer ", calls **JwtTokenService.extractUsername(token)**.
   - If username is valid → creates **StompPrincipal(username)** and sets it on the message: **accessor.setUser(principal)**. So for the rest of the session, STOMP knows the user by this principal.
   - If no/invalid token → principal is not set (connection still proceeds; later SEND might fail if code checks principal).
3. **Message broker:** **Application destination prefix** = `/app`, **Broker prefix** = `/topic` (and `/queue`). So client sends to `/app/...` and subscribes to `/topic/...`.
4. Client sends a message to **/app/greet** (with token in headers if needed). **ChatUserController.handleGreeting()**:
   - **ChatUserService.greetingHandler(token)**:
     - Extracts username from token again.
     - **UserRepository.updateUserStatus(username, UserStatus.ACTIVE)** (async) → set user ACTIVE in DB.
     - Puts **user** into **ChatUserService**’s in-memory **ConcurrentHashMap** `users` (key = username). So "online" users for WebSocket are this map.
   - **messagingTemplate.convertAndSend("/topic/greet", "websocket connection established")** → everyone subscribed to /topic/greet gets that string.

**Summary:** WebSocket connect → interceptor parses JWT and sets Principal → /app/greet updates user status and adds user to in-memory `users` map, then broadcasts to /topic/greet.

---

### 2.9 WebSocket: Join Room

1. **Client** sends to **/app/chat.join** with payload **{ username, roomId }**.
2. **ChatRoomController.joinRoom()** → **ChatUserService.joiningRequestHandler(username, roomId)**:
   - Gets **User** from in-memory **users** map (must have called /app/greet first so user is in map). If not found → logs "No user found" and returns.
   - **RoomRepository.findRoomByID(roomId)** → check room exists in MongoDB.
   - **RoomService.addUserToRoom(user, roomId)** → in the current code this only **finds** the room and logs; it does **not** persist "user X in room Y" anywhere. So "join" is more of a client-side subscription; server just validates user and room exist.

**Summary:** Join = user must be in `users` map (greet first), room must exist in DB. No DB write for membership in this implementation.

---

### 2.10 WebSocket: Send Chat Message (Full Pipeline)

1. **Client** sends to **/app/chat.send** with **header roomId** and payload **{ sender, message, timeStamp }** (MessageDTO).
2. **ChatUserController.handleMessage()**:
   - Gets **roomID** from header.
   - **ChatUserService.publishMessageToKafka(messageDTO, roomId)**:
     - Validates messageDTO and roomId non-empty; **ObjectId.isValid(roomId)** for MongoDB ID.
     - Builds **Message** (roomId, sender, message, timeStamp) and calls **KafkaPublisherService.sendEvent(message)**.
   - **KafkaPublisherService**: **kafkaTemplate.send("chat", message)** → sends **Message** to Kafka **topic "chat"** (JSON serialized). Async (CompletableFuture); logs success/failure.
   - **ChatUserController** then does **messagingTemplate.convertAndSend("/topic/chat/" + roomID, message)** → so **all subscribers to that room** (including sender) get the message **immediately** for real-time UI. Persistence is separate (Kafka path).
3. **Kafka consumer** (**KafkaListenerService**): **@KafkaListener(topics = "chat", groupId = "chat-group")** method **consumeEvent(Message message)** is invoked when a message is produced.
   - **MessageBuffer.addMessage(message)**:
     - **synchronized** add to in-memory **ArrayList** `buffer`.
     - If **buffer.size() >= BATCH_SIZE (10)** → **flushBuffer()**:
       - **RoomRepository.addMessages(buffer)** → **MongoTemplate.insert(messageList, Message.class)** into collection **`messages`**.
       - **buffer.clear()**.
   - So messages are **batched**: every 10 messages trigger one bulk insert to MongoDB. Fewer than 10 → stay in buffer until next 10 or restart (then lost unless you have a shutdown flush).
4. **Summary:** Send message → (1) publish to Kafka topic "chat", (2) broadcast same message to /topic/chat/{roomId} for real-time. Kafka consumer appends to buffer; every 10 messages flush to MongoDB.

---

### 2.11 WebSocket: Chat History

1. **Client** sends to **/app/chat.history** with **header roomId**.
2. **ChatUserController.handleHistory()** → **ChatUserService.chatHistoryHandler(roomId)**:
   - If **MessageBuffer** has messages, **filter** by roomId and return that list if non-empty.
   - Else **RoomRepository.getRoomSpecificMessages(roomId)** → **MongoTemplate.find** with criteria **roomId** on collection **messages**.
   - Converts to **MessageDTO** list and **messagingTemplate.convertAndSend("/topic/history/" + roomId, dtoList)**.
3. Client subscribed to **/topic/history/{roomId}** receives the list.

**Summary:** History = room-specific messages from in-memory buffer first; if none, from MongoDB.

---

### 2.12 WebSocket: Fetch Online Users

1. **Client** sends to **/app/users**.
2. **ChatUserController.fetchUsers()** → **ChatUserService.fetchUser()**:
   - **UserRepository.findAllUser()** → **MongoTemplate.findAll(User.class)**. So this is **all users in DB**, not just "online" from the `users` map. Method is **@Cacheable("userCache")** → result cached in Redis (RedisCacheManager, 30 min TTL from RedisConfig).
   - Converts to **UserDTO** list and **convertAndSend("/topic/users", list)**.
3. Client subscribed to **/topic/users** gets the list.

**Summary:** "Online users" endpoint actually returns **all users** from MongoDB, cached in Redis for 30 minutes.

---

## 3. Where Redis Is Used (Exact Keys and Purpose)

| Purpose | Key(s) | TTL | Who Writes | Who Reads | Who Deletes |
|--------|--------|-----|------------|-----------|-------------|
| **OTP during signup** | `otp:<email>` | 5 minutes | RedisService.cacheOTPWithTTL (from OTPService.generateOTPForUser) | RedisService.getOTP (verifyOTP, getOTPForDemo) | RedisService.removeOTP (after verify, or on resend before new OTP) |
| **User before verification** | `user:<email>` | None | RedisService.cacheUserWithTTL (AuthService after generating OTP) | RedisService.getUser (createUser, resendOTP) | RedisService.removeUser (after createUser) |
| **Cache for "all users"** | (Spring Cache abstraction; key by method) | 30 min | N/A (cache populated on first findAllUser) | ChatUserService.fetchUser → UserRepository.findAllUser | @CacheEvict on handleLogout (clears entire userCache) |

- **RedisConfig**: **RedisTemplate** with String key serializer, GenericJackson2JsonRedisSerializer for values. **RedisCacheManager** with default TTL 30 minutes for **@Cacheable** (e.g. userCache).
- **application.properties**: **spring.data.redis.host/port/password** from env (REDIS_HOST, REDIS_PORT, REDIS_PASSWORD). No TTL in properties; 5 min for OTP is in code (TimeUnit.MINUTES in RedisService.cacheOTPWithTTL).

---

## 4. Where Kafka Is Used (Topic, Producer, Consumer, Buffer)

| Component | Role |
|-----------|------|
| **Topic name** | `"chat"` |
| **Creation** | **KafkaProducerConfig** defines a **NewTopic** bean: name "chat", 1 partition, replication factor 1. |
| **Producer** | **KafkaPublisherService.sendEvent(Message)** → **KafkaTemplate.send("chat", message)**. Key not set (null). Value = **Message** (roomId, sender, message, timeStamp) serialized as JSON (**JsonSerializer** in application.properties). |
| **Consumer** | **KafkaListenerService.consumeEvent(Message message)** with **@KafkaListener(topics = "chat", groupId = "chat-group")**. Deserializer: **JsonDeserializer**, trusted packages **com.connect.model** so Message is deserialized. |
| **After consume** | **MessageBuffer.addMessage(message)** → in-memory **ArrayList**. When size ≥ **10**, **flushBuffer()** → **RoomRepository.addMessages(buffer)** (bulk insert into MongoDB **messages**), then **buffer.clear()**. |
| **Why Kafka** | Decouples "receiving chat message" from "writing to DB". Multiple consumers could be added (e.g. analytics). Batching reduces DB writes. |

- **application.properties**: **spring.kafka.producer/consumer.bootstrap-servers** = **KAFKA_SERVER** (env). Producer: StringSerializer key, JsonSerializer value. Consumer: StringDeserializer key, JsonDeserializer value.

---

## 5. Package-by-Package (What Each Class Does)

### controller
- **AuthController** (`/auth`): signup, verifyOTP, resendOTP, login, logout, getOTPForDemo (demo only).
- **ChatRoomController**: REST — createRoom, fetchRooms (getall), deleteRoom, deleteAllMyRooms. WebSocket — **@MessageMapping("/chat.join")** joinRoom.
- **ChatUserController**: All WebSocket: **/app/greet**, **/app/chat.send**, **/app/chat.history**, **/app/users**. Uses SimpMessagingTemplate to send to /topic/*.
- **HealthController**: GET /health → "Health is ok".
- **TokenController**: GET /api/verify-token → validates JWT from header, returns "Authorized" or 401.

### service
- **AuthService**: signupHandler (DB check, OTP, Redis user), resendOTP, createUser (verify OTP, Redis user → MongoDB), loginHandler (authenticate, JWT, async status), handleLogout (status update), getOTPForDemo.
- **OTPService**: generateOTPForUser (4-digit, Redis 5 min), verifyOTP (read from Redis, compare), getOTPForDemo (read OTP from Redis).
- **RedisService**: cacheUserWithTTL, getUser, removeUser; cacheOTPWithTTL (5 min), getOTP, removeOTP. All use RedisTemplate<String, Object>.
- **EmailService**: sendEmail — if not configured or DEMO_MODE, skips send and logs; otherwise JavaMailSender. Uses EmailUtil for body template.
- **JwtTokenService**: extractUsername(token) using JwtUtil.extractClaims → getSubject.
- **RoomService**: init() @PostConstruct — ensure "general" room exists. addUserToRoom (find room only). addNewRoom (set admin, insert). getRooms, deleteRoom (admin check via findRoomByIDAndAdminUserId), deleteAllRoomsForUser, getRoomsByAdmin.
- **ChatUserService**: greetingHandler (JWT → username, update status, put in users map). joiningRequestHandler (user from map, room from DB, addUserToRoom). publishMessageToKafka (build Message, call KafkaPublisherService). chatHistoryHandler (buffer by roomId else DB). fetchUser (findAllUser, @Cacheable userCache).

### repository
- **UserRepository**: createUser, findByEmail, findByUsername, updateUserStatus (@Async), findAllUser. All MongoTemplate.
- **RoomRepository**: addRoom, getRooms, findRoomByID, findRoomByIDAndAdminUserId, findRoomByName, addMessageToRoom, addMessages, getRoomSpecificMessages, deleteRoomById, deleteRoomsByAdminUserId, findRoomsByAdminUserId.

### kafka
- **KafkaPublisherService**: sendEvent(Message) → kafkaTemplate.send("chat", message).
- **KafkaListenerService**: @KafkaListener("chat", "chat-group") consumeEvent(Message) → messageBuffer.addMessage(message).

### buffer
- **MessageBuffer**: synchronized ArrayList, BATCH_SIZE=10. addMessage → add; if size>=10 flushBuffer (RoomRepository.addMessages, clear). getMessages, size, flushIfNeeded.

### config
- **SecurityConfig**: CSRF off, CORS from corsConfigurationSource (frontend + localhost:8000), stateless session, **authorizeHttpRequests** — /ws/** permitAll, **anyRequest().permitAll()**. No JWT filter; controllers that need auth read token manually. PasswordEncoder BCrypt, AuthenticationManager bean.
- **WebSocketConfig**: EnableWebSocketMessageBroker. Broker /topic, /queue; app prefix /app. Endpoint /ws, SockJS, allowed origins. ChannelInterceptor: on CONNECT, read Authorization Bearer, JwtTokenService.extractUsername, set StompPrincipal as user.
- **RedisConfig**: RedisTemplate (String keys, JSON values), RedisCacheManager 30 min default.
- **KafkaProducerConfig**: NewTopic "chat", 1 partition, 1 replica.
- **AsyncConfiguration**: @EnableAsync, bean asyncTaskExecutor (ThreadPoolTaskExecutor, core 4, max 4, queue 50). Used by @Async updateUserStatus.

### model (MongoDB documents)
- **User**: id (ObjectId), username, email, password, userRole (List UserRole), status (UserStatus). Collection **users**. Indexed unique on username, email.
- **Room**: roomId (String, @Id), roomName, roomDescription, timeStamp, moderators, admin (DBRef User), coAdmin, allUsers. Collection **rooms**.
- **Message**: id (ObjectId), roomId, sender, message, timeStamp. Collection **messages**.

### dto
- **OtpDTO**: otp, email. Used in Redis and API.
- **LoginUserDTO**: email, password. Login request body.
- **MessageDTO**: sender, message, timeStamp. WebSocket payload; constructor from Message.
- **RoomDTO**: built from Room for API response.
- **UserDTO**: built from User for WebSocket /topic/users.

### security
- **CustomUserDetails**: implements UserDetails; holds username, email, password, authorities from User. Used by Spring Security for login.
- **CustomUserDetailsImpl**: UserDetailsService; loadUserByUsername(email) → UserRepository.findByEmail → CustomUserDetails.
- **StompPrincipal**: Principal with name = username. Set on WebSocket CONNECT so STOMP session is associated with a user.

### utils
- **JwtUtil**: generateToken(username, email), extractClaims, isTokenValid, isTokenExpired, getExpirationDate. HS256, 1h expiry, key from jwt.secret.key.
- **EmailUtil**: provides email body template (e.g. "Hello {0}, OTP is {1}").

### exception
- **DuplicateResourceException**, **InvalidUserException**, **UserCreationException**, **TimeoutException**: custom exceptions.
- **GlobalExceptionHandler** (@RestControllerAdvice): maps each to HTTP status (400, 500, 504) and body with "response" message. Also MongoTimeoutException, generic Exception.

### enums
- **UserRole**: USER, MOD, ADMIN.
- **UserStatus**: ACTIVE, INACTIVE.

---

## 6. Configuration (Env Vars and application.properties)

- **MONGO_URI** → spring.data.mongodb.uri  
- **REDIS_HOST**, **REDIS_PORT**, **REDIS_PASSWORD** → spring.data.redis.*  
- **KAFKA_SERVER** → spring.kafka.producer/consumer.bootstrap-servers  
- **JWT_SECRET** → jwt.secret.key  
- **MAIL_USERNAME**, **MAIL_PASSWORD** → spring.mail.*  
- **FRONTEND_ORIGIN** → frontend.origin (CORS and WebSocket allowed origins)  
- **DEMO_MODE** (env or system property) → EmailService skips sending if true or email not configured  

JWT expiry is hardcoded in JwtUtil: 1000*60*60 ms = 1 hour. OTP TTL 5 minutes is in RedisService. Message buffer BATCH_SIZE 10 is in MessageBuffer. Redis cache TTL 30 minutes is in RedisConfig.

---

## 7. Security (What Is Protected and How)

- **REST:** SecurityConfig has **anyRequest().permitAll()** — no global denial. **Room create/delete** and **Token verify** manually read `Authorization: Bearer <token>` and call **JwtTokenService.extractUsername()**. Invalid/missing token → 401/403 in controller. So "protection" is in controller logic, not a filter.
- **WebSocket:** CONNECT frame must send **Authorization: Bearer <token>**. WebSocketConfig’s interceptor parses JWT and sets **StompPrincipal**. If token invalid, principal is null; some handlers (e.g. greet) may still run but can fail later. No hard "reject connection" in code.
- **Login:** Spring Security **AuthenticationManager** + **CustomUserDetailsImpl** (load by email from MongoDB) + **BCrypt** password check. On success, JWT is generated and returned; no JWT filter on REST, so REST is effectively "open" except where controllers check token themselves.

---

## 8. Minor Details (Interview Gold)

- **Room ID:** Stored as **String** in Room (roomId is @Id). MongoDB can generate ObjectId; here Room uses String as id (MongoDB will set _id when not provided or use what you set). Messages store **roomId** as String to match.
- **Message timeStamp:** Message model has **LocalDateTime**; MessageDTO has **LocalDateTime**. Kafka serialization/deserialization must handle that (Spring Kafka JsonSerializer/JsonDeserializer with default config).
- **Logout:** Only updates **User.status** to ACTIVE (same as login flow). No token invalidation (JWT is stateless). So "logout" is just a status update in DB.
- **Join room:** Does not insert into any "room_members" collection. ChatUserService.addUserToRoom only finds the room. So room "membership" for receive is implicit (whoever subscribes to /topic/chat/{roomId}).
- **General room:** RoomService.init() ensures a room with name "general" exists at startup (find or create).
- **Async:** Only **UserRepository.updateUserStatus** is @Async (login and greet). Executor is **asyncTaskExecutor** (4 threads, queue 50).
- **Caching:** Only **ChatUserService.fetchUser()** is @Cacheable("userCache"). Evicted on **AuthService.handleLogout** via @CacheEvict(value = "userCache", allEntries = true).

---

You now have the full journey, every use of Redis and Kafka, each component’s role, and the small details. Use this to answer any “how does X work?” or “where is Y used?” in interviews.
