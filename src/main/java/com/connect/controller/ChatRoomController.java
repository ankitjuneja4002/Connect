package com.connect.controller;

// Room associate handler functions are found here.

import com.connect.dto.RoomDTO;
import com.connect.model.Room;
import com.connect.service.ChatUserService;
import com.connect.service.JwtTokenService;
import com.connect.service.RoomService;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

@RestController
@Slf4j
@RequiredArgsConstructor
public class ChatRoomController {

    private final ChatUserService chatUserService;
    private final RoomService roomService;
    private final JwtTokenService jwtTokenService;
    private final SimpMessagingTemplate messagingTemplate;

    // Route for handling the joining message.
    @MessageMapping("/chat.join")
    public void joinRoom(@Payload Map<String, String> joinReq) {
        String username = joinReq.get("username");
        String roomId = joinReq.get("roomId");
        if (username.isEmpty() || roomId.isEmpty()) {
            log.error("Bad Request | Data not found");
            return;
        }
        chatUserService.joiningRequestHandler(username, roomId);
    }

    // Handler when the user creates a new room.
    // Person who is creating the room must give the necessary information as in body.
    @PostMapping("/room/create")
    public ResponseEntity<Map<String, String>> createRoom(@RequestBody Room room, HttpServletRequest request) {

        log.info("New Room request");
        String rawToken = request.getHeader("Authorization");

        return Optional.ofNullable(jwtTokenService.extractUsername(rawToken.substring(7)))
                .flatMap(username -> Optional.ofNullable(roomService.addNewRoom(room, username))
                        .map(newRoom -> ResponseEntity.ok(Map.of("response", "Room created successfully.")))
                )
                .orElseGet(() -> {
                    return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                            .body(Map.of("response", "Invalid Token or Room Creation Failed"));
                });
    }

    @GetMapping("/room/getall")
    public ResponseEntity<List<RoomDTO>> fetchRooms() {
        return ResponseEntity
                .status(HttpStatus.OK)
                .body(roomService.getRooms()
                        .stream()
                        .map(RoomDTO::new)
                        .collect(Collectors.toList()));
    }

    @DeleteMapping("/room/delete/{roomId}")
    public ResponseEntity<Map<String, String>> deleteRoom(
            @PathVariable("roomId") String roomId,
            HttpServletRequest request) {

        String rawToken = request.getHeader("Authorization");
        if (rawToken == null || !rawToken.startsWith("Bearer ")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("response", "Missing or invalid Authorization header"));
        }

        return Optional.ofNullable(jwtTokenService.extractUsername(rawToken.substring(7)))
                .filter(username -> roomService.deleteRoom(roomId, username))
                .map(username -> ResponseEntity.ok(Map.of("response", "Room deleted successfully")))
                .orElseGet(() -> ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("response", "Room not found or you are not the admin of this room")));
    }

    @DeleteMapping("/room/my-rooms")
    public ResponseEntity<Map<String, Object>> deleteAllMyRooms(HttpServletRequest request) {

        String rawToken = request.getHeader("Authorization");
        if (rawToken == null || !rawToken.startsWith("Bearer ")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("response", "Missing or invalid Authorization header"));
        }

        return Optional.ofNullable(jwtTokenService.extractUsername(rawToken.substring(7)))
                .map(username -> {
                    long deleted = roomService.deleteAllRoomsForUser(username);
                    return ResponseEntity.ok(Map.<String, Object>of(
                            "response", "Rooms deleted successfully",
                            "deletedCount", deleted));
                })
                .orElseGet(() -> ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(Map.of("response", "Invalid token")));
    }
}
