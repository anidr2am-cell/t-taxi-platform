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

  async findRoomByBookingId(conn, bookingId) {
    const [rows] = await conn.query(
      `
        SELECT id, booking_id, room_code, is_active, is_archived,
               archived_at, archived_by, archive_reason, created_at
        FROM chat_rooms
        WHERE booking_id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [bookingId],
    );
    return rows[0] ?? null;
  }

  async findRoomByBookingIdForUpdate(conn, bookingId) {
    const [rows] = await conn.query(
      `
        SELECT id, booking_id, room_code, is_active, is_archived,
               archived_at, archived_by, archive_reason, created_at
        FROM chat_rooms
        WHERE booking_id = ? AND deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [bookingId],
    );
    return rows[0] ?? null;
  }

  async findRoomByBookingNumber(conn, bookingNumber) {
    const [rows] = await conn.query(
      `
        SELECT cr.id, cr.booking_id, cr.room_code, cr.is_active,
               cr.is_archived, cr.archived_at, cr.archived_by,
               cr.archive_reason, cr.created_at,
               b.booking_number, b.status AS booking_status, b.customer_name,
               b.customer_user_id, b.driver_id
        FROM chat_rooms cr
        INNER JOIN bookings b ON b.id = cr.booking_id AND b.deleted_at IS NULL
        WHERE b.booking_number = ? AND cr.deleted_at IS NULL
        LIMIT 1
      `,
      [bookingNumber],
    );
    return rows[0] ?? null;
  }

  async insertParticipant(conn, chatRoomId, participant) {
    const [result] = await conn.query(
      `
        INSERT INTO chat_participants (
          chat_room_id, user_id, participant_role, display_name
        ) VALUES (?, ?, ?, ?)
      `,
      [
        chatRoomId,
        participant.userId ?? null,
        participant.participantRole,
        participant.displayName,
      ],
    );
    return result.insertId;
  }

  async findParticipant(conn, chatRoomId, participantRole, userId) {
    const [rows] = await conn.query(
      `
        SELECT id, chat_room_id, user_id, participant_role, display_name,
               last_read_at, joined_at, created_at
        FROM chat_participants
        WHERE chat_room_id = ?
          AND participant_role = ?
          AND deleted_at IS NULL
          AND ${userId == null ? "user_id IS NULL" : "user_id = ?"}
        LIMIT 1
      `,
      userId == null
        ? [chatRoomId, participantRole]
        : [chatRoomId, participantRole, userId],
    );
    return rows[0] ?? null;
  }

  async findParticipantById(conn, participantId) {
    const [rows] = await conn.query(
      `
        SELECT id, chat_room_id, user_id, participant_role, display_name, last_read_at
        FROM chat_participants
        WHERE id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [participantId],
    );
    return rows[0] ?? null;
  }

  async findGuestParticipant(conn, chatRoomId) {
    const [rows] = await conn.query(
      `
        SELECT id, chat_room_id, user_id, participant_role, display_name, last_read_at
        FROM chat_participants
        WHERE chat_room_id = ?
          AND participant_role = 'CUSTOMER'
          AND user_id IS NULL
          AND deleted_at IS NULL
        LIMIT 1
      `,
      [chatRoomId],
    );
    return rows[0] ?? null;
  }

  async deactivateParticipant(conn, chatRoomId, participantRole, userId) {
    const [result] = await conn.query(
      `
        UPDATE chat_participants
        SET deleted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
        WHERE chat_room_id = ?
          AND participant_role = ?
          AND user_id = ?
          AND deleted_at IS NULL
      `,
      [chatRoomId, participantRole, userId],
    );
    return result.affectedRows;
  }

  async reactivateParticipant(
    conn,
    chatRoomId,
    participantRole,
    userId,
    displayName,
  ) {
    const [result] = await conn.query(
      `
        UPDATE chat_participants
        SET deleted_at = NULL,
            display_name = ?,
            joined_at = CURRENT_TIMESTAMP,
            last_read_at = NULL,
            updated_at = CURRENT_TIMESTAMP
        WHERE chat_room_id = ?
          AND participant_role = ?
          AND user_id = ?
          AND deleted_at IS NOT NULL
      `,
      [displayName, chatRoomId, participantRole, userId],
    );
    return result.affectedRows;
  }

  async listParticipants(conn, chatRoomId) {
    const [rows] = await conn.query(
      `
        SELECT id, chat_room_id, user_id, participant_role, display_name, last_read_at
        FROM chat_participants
        WHERE chat_room_id = ? AND deleted_at IS NULL
        ORDER BY id ASC
      `,
      [chatRoomId],
    );
    return rows;
  }

  async insertMessage(conn, message) {
    const [result] = await conn.query(
      `
        INSERT INTO chat_messages (
          chat_room_id,
          sender_user_id,
          sender_participant_id,
          sender_role,
          sender_name,
          message_type,
          content,
          client_message_id,
          message_status
        ) VALUES (?, ?, ?, ?, ?, 'TEXT', ?, ?, 'SENT')
      `,
      [
        message.chatRoomId,
        message.senderUserId ?? null,
        message.senderParticipantId,
        message.senderRole,
        message.senderName,
        message.content,
        message.clientMessageId,
      ],
    );
    return result.insertId;
  }

  async findMessageByClientId(
    conn,
    chatRoomId,
    senderParticipantId,
    clientMessageId,
  ) {
    const [rows] = await conn.query(
      `
        SELECT
          id, chat_room_id, sender_participant_id, sender_role, sender_name,
          content, client_message_id, is_hidden, hidden_at, hidden_by,
          hide_reason, created_at
        FROM chat_messages
        WHERE chat_room_id = ?
          AND sender_participant_id = ?
          AND client_message_id = ?
          AND deleted_at IS NULL
        LIMIT 1
      `,
      [chatRoomId, senderParticipantId, clientMessageId],
    );
    return rows[0] ?? null;
  }

  async findMessageById(conn, messageId, chatRoomId = null) {
    const params = [messageId];
    let sql = `
      SELECT
        id, chat_room_id, sender_participant_id, sender_role, sender_name,
        content, client_message_id, is_hidden, hidden_at, hidden_by,
        hide_reason, created_at
      FROM chat_messages
      WHERE id = ? AND deleted_at IS NULL
    `;
    if (chatRoomId != null) {
      sql += " AND chat_room_id = ?";
      params.push(chatRoomId);
    }
    sql += " LIMIT 1";
    const [rows] = await conn.query(sql, params);
    return rows[0] ?? null;
  }

  async listMessages(conn, chatRoomId, { cursor = null, limit = 50 } = {}) {
    const boundedLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
    const params = [chatRoomId];
    let cursorSql = "";
    if (cursor) {
      cursorSql =
        " AND (created_at < (SELECT created_at FROM chat_messages WHERE id = ?) OR (created_at = (SELECT created_at FROM chat_messages WHERE id = ?) AND id < ?))";
      params.push(cursor, cursor, cursor);
    }
    params.push(boundedLimit);
    const [rows] = await conn.query(
      `
        SELECT
          id, sender_participant_id, sender_role, sender_name,
          content, client_message_id, is_hidden, hidden_at, hidden_by,
          hide_reason, created_at
        FROM chat_messages
        WHERE chat_room_id = ? AND deleted_at IS NULL
        ${cursorSql}
        ORDER BY created_at DESC, id DESC
        LIMIT ?
      `,
      params,
    );
    return rows;
  }

  async countUnreadForParticipant(conn, chatRoomId, participant) {
    const [rows] = await conn.query(
      `
        SELECT COUNT(*) AS unread_count
        FROM chat_messages m
        WHERE m.chat_room_id = ?
          AND m.deleted_at IS NULL
          AND m.is_hidden = 0
          AND m.sender_participant_id <> ?
          AND (
            ? IS NULL
            OR m.created_at > ?
          )
      `,
      [
        chatRoomId,
        participant.id,
        participant.last_read_at,
        participant.last_read_at,
      ],
    );
    return Number(rows[0]?.unread_count ?? 0);
  }

  async updateParticipantLastRead(conn, participantId, readAt) {
    await conn.query(
      `
        UPDATE chat_participants
        SET last_read_at = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [readAt, participantId],
    );
  }

  async insertMessageRead(conn, messageId, participantId) {
    await conn.query(
      `
        INSERT IGNORE INTO chat_message_reads (chat_message_id, chat_participant_id)
        VALUES (?, ?)
      `,
      [messageId, participantId],
    );
  }

  async findLastMessage(conn, chatRoomId) {
    const [rows] = await conn.query(
      `
        SELECT id, sender_name, content, created_at
        FROM chat_messages
        WHERE chat_room_id = ? AND deleted_at IS NULL AND is_hidden = 0
        ORDER BY created_at DESC, id DESC
        LIMIT 1
      `,
      [chatRoomId],
    );
    return rows[0] ?? null;
  }

  async countAdminUnread(conn, chatRoomId, adminParticipantId) {
    const participant = await this.findParticipantById(
      conn,
      adminParticipantId,
    );
    if (!participant) return 0;
    return this.countUnreadForParticipant(conn, chatRoomId, participant);
  }

  async listAdminChatSummaries(
    conn,
    adminUserId,
    { search = null, unreadOnly = false, archived = false, limit = 20, offset = 0 } = {},
  ) {
    const boundedLimit = Math.min(Math.max(Number(limit) || 20, 1), 100);
    const boundedOffset = Math.max(Number(offset) || 0, 0);
    const params = [adminUserId];
    let searchSql = "";
    if (search) {
      searchSql = `
        AND (
          b.booking_number LIKE ?
          OR b.customer_name LIKE ?
          OR d.name LIKE ?
        )
      `;
      const term = `%${search}%`;
      params.push(term, term, term);
    }
    let unreadSql = "";
    if (unreadOnly) {
      unreadSql = `
        AND EXISTS (
          SELECT 1
          FROM chat_messages m
          INNER JOIN chat_participants ap ON ap.chat_room_id = cr.id
            AND ap.user_id = ?
            AND ap.participant_role = 'ADMIN'
            AND ap.deleted_at IS NULL
          WHERE m.chat_room_id = cr.id
            AND m.deleted_at IS NULL
            AND m.is_hidden = 0
            AND m.sender_participant_id <> ap.id
            AND (ap.last_read_at IS NULL OR m.created_at > ap.last_read_at)
        )
      `;
      params.push(adminUserId);
    }
    params.push(boundedLimit, boundedOffset);
    const [rows] = await conn.query(
      `
        SELECT
          cr.id AS room_id,
          cr.room_code,
          cr.is_active,
          cr.is_archived,
          cr.archived_at,
          cr.archive_reason,
          cr.created_at AS room_created_at,
          b.booking_number,
          b.status AS booking_status,
          b.customer_name,
          d.name AS driver_name,
          lm.id AS last_message_id,
          lm.content AS last_message_text,
          lm.created_at AS last_message_at,
          ap.id AS admin_participant_id,
          ap.last_read_at AS admin_last_read_at
        FROM chat_rooms cr
        INNER JOIN bookings b ON b.id = cr.booking_id AND b.deleted_at IS NULL
        LEFT JOIN drivers d ON d.id = b.driver_id
        LEFT JOIN chat_participants ap ON ap.chat_room_id = cr.id
          AND ap.user_id = ?
          AND ap.participant_role = 'ADMIN'
          AND ap.deleted_at IS NULL
        LEFT JOIN chat_messages lm ON lm.id = (
          SELECT id FROM chat_messages
          WHERE chat_room_id = cr.id AND deleted_at IS NULL AND is_hidden = 0
          ORDER BY created_at DESC, id DESC
          LIMIT 1
        )
        WHERE cr.deleted_at IS NULL
          AND cr.is_archived = ?
        ${searchSql}
        ${unreadSql}
        ORDER BY COALESCE(lm.created_at, cr.created_at) DESC
        LIMIT ? OFFSET ?
      `,
      [params[0], archived ? 1 : 0, ...params.slice(1)],
    );
    return rows;
  }

  async countAdminChatSummaries(
    conn,
    adminUserId,
    { search = null, unreadOnly = false, archived = false } = {},
  ) {
    const params = [];
    let searchSql = "";
    if (search) {
      searchSql = `
        AND (
          b.booking_number LIKE ?
          OR b.customer_name LIKE ?
          OR d.name LIKE ?
        )
      `;
      const term = `%${search}%`;
      params.push(term, term, term);
    }
    let unreadSql = "";
    if (unreadOnly) {
      unreadSql = `
        AND EXISTS (
          SELECT 1
          FROM chat_messages m
          INNER JOIN chat_participants ap ON ap.chat_room_id = cr.id
            AND ap.user_id = ?
            AND ap.participant_role = 'ADMIN'
            AND ap.deleted_at IS NULL
          WHERE m.chat_room_id = cr.id
            AND m.deleted_at IS NULL
            AND m.is_hidden = 0
            AND m.sender_participant_id <> ap.id
            AND (ap.last_read_at IS NULL OR m.created_at > ap.last_read_at)
        )
      `;
      params.push(adminUserId);
    }
    const [rows] = await conn.query(
      `
        SELECT COUNT(*) AS total
        FROM chat_rooms cr
        INNER JOIN bookings b ON b.id = cr.booking_id AND b.deleted_at IS NULL
        LEFT JOIN drivers d ON d.id = b.driver_id
        WHERE cr.deleted_at IS NULL
          AND cr.is_archived = ?
        ${searchSql}
        ${unreadSql}
      `,
      [archived ? 1 : 0, ...params],
    );
    return Number(rows[0]?.total ?? 0);
  }

  async findMessageWithRoomForUpdate(conn, messageId) {
    const [rows] = await conn.query(
      `
        SELECT
          m.id,
          m.chat_room_id,
          m.sender_role,
          m.sender_name,
          m.content,
          m.is_hidden,
          m.hide_reason,
          cr.booking_id,
          b.booking_number
        FROM chat_messages m
        INNER JOIN chat_rooms cr ON cr.id = m.chat_room_id
          AND cr.deleted_at IS NULL
        INNER JOIN bookings b ON b.id = cr.booking_id
          AND b.deleted_at IS NULL
        WHERE m.id = ? AND m.deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [messageId],
    );
    return rows[0] ?? null;
  }

  async hideMessage(conn, messageId, { actorUserId, reason }) {
    const [result] = await conn.query(
      `
        UPDATE chat_messages
        SET
          is_hidden = 1,
          hidden_at = CURRENT_TIMESTAMP,
          hidden_by = ?,
          hide_reason = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [actorUserId, reason, messageId],
    );
    return result.affectedRows;
  }

  async restoreMessage(conn, messageId) {
    const [result] = await conn.query(
      `
        UPDATE chat_messages
        SET
          is_hidden = 0,
          hidden_at = NULL,
          hidden_by = NULL,
          hide_reason = NULL,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [messageId],
    );
    return result.affectedRows;
  }

  async findRoomsForArchiveByBookingNumbersForUpdate(conn, bookingNumbers) {
    if (!bookingNumbers.length) return [];
    const placeholders = bookingNumbers.map(() => '?').join(', ');
    const [rows] = await conn.query(
      `
        SELECT
          cr.id,
          cr.booking_id,
          cr.room_code,
          cr.is_archived,
          cr.archive_reason,
          b.booking_number,
          b.status AS booking_status
        FROM chat_rooms cr
        INNER JOIN bookings b ON b.id = cr.booking_id
          AND b.deleted_at IS NULL
        WHERE b.booking_number IN (${placeholders})
          AND cr.deleted_at IS NULL
        FOR UPDATE
      `,
      bookingNumbers,
    );
    return rows;
  }

  async archiveRooms(conn, roomIds, { actorUserId, reason }) {
    if (!roomIds.length) return 0;
    const placeholders = roomIds.map(() => '?').join(', ');
    const [result] = await conn.query(
      `
        UPDATE chat_rooms
        SET
          is_archived = 1,
          archived_at = CURRENT_TIMESTAMP,
          archived_by = ?,
          archive_reason = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE id IN (${placeholders})
          AND deleted_at IS NULL
      `,
      [actorUserId, reason, ...roomIds],
    );
    return result.affectedRows;
  }

  async restoreRoom(conn, roomId) {
    const [result] = await conn.query(
      `
        UPDATE chat_rooms
        SET
          is_archived = 0,
          archived_at = NULL,
          archived_by = NULL,
          archive_reason = NULL,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [roomId],
    );
    return result.affectedRows;
  }
}

module.exports = ChatRepository;
