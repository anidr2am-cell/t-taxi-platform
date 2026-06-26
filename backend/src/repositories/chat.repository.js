class ChatRepository {
  async insertRoom(conn, bookingId, roomCode) {
    const [result] = await conn.query(
      `
        INSERT INTO chat_rooms (booking_id, room_code, is_active)
        VALUES (?, ?, 1)
      `,
      [bookingId, roomCode],
    );
    return result.insertId;
  }

  async insertParticipant(conn, chatRoomId, participant) {
    await conn.query(
      `
        INSERT INTO chat_participants (
          chat_room_id, user_id, participant_role, display_name
        ) VALUES (?, ?, ?, ?)
      `,
      [
        chatRoomId,
        participant.userId,
        participant.participantRole,
        participant.displayName,
      ],
    );
  }
}

module.exports = ChatRepository;
