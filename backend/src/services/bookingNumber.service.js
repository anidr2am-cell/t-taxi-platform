class BookingNumberService {
  formatDatePrefix(date = new Date()) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}${m}${d}`;
  }

  async generateNext(conn) {
    const datePrefix = this.formatDatePrefix();

    const [existing] = await conn.query(
      `
        SELECT last_sequence
        FROM booking_number_sequences
        WHERE date_prefix = ?
        FOR UPDATE
      `,
      [datePrefix],
    );

    let sequence;
    if (!existing.length) {
      sequence = 1;
      await conn.query(
        `
          INSERT INTO booking_number_sequences (date_prefix, last_sequence)
          VALUES (?, ?)
        `,
        [datePrefix, sequence],
      );
    } else {
      sequence = existing[0].last_sequence + 1;
      await conn.query(
        `
          UPDATE booking_number_sequences
          SET last_sequence = ?
          WHERE date_prefix = ?
        `,
        [sequence, datePrefix],
      );
    }

    return `TX${datePrefix}${String(sequence).padStart(4, '0')}`;
  }
}

module.exports = BookingNumberService;
