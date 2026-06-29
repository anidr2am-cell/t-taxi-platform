const logger = require('../utils/logger');

const TIMEZONE = 'Asia/Bangkok';

class AdminDashboardService {
  constructor(repository, now = () => new Date()) {
    this.repository = repository;
    this.now = now;
  }

  thailandDateParts(date) {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: TIMEZONE,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date);
    const part = (type) => parts.find((item) => item.type === type)?.value;
    return {
      year: Number(part('year')),
      month: Number(part('month')),
      day: Number(part('day')),
      date: `${part('year')}-${part('month')}-${part('day')}`,
    };
  }

  serviceDayRange(date = this.now()) {
    const parts = this.thailandDateParts(date);
    const next = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + 1));
    const nextParts = this.thailandDateParts(next);
    return {
      date: parts.date,
      start: `${parts.date} 00:00:00`,
      end: `${nextParts.date} 00:00:00`,
    };
  }

  number(value) {
    return Number(value ?? 0);
  }

  money(value) {
    return Number(value ?? 0);
  }

  mapRevenue(rows) {
    if (!rows.length) {
      return {
        currency: 'THB',
        todayBooked: 0,
        todayCompleted: 0,
        byCurrency: [],
      };
    }

    const byCurrency = rows.map((row) => ({
      currency: row.currency,
      todayBooked: this.money(row.today_booked),
      todayCompleted: this.money(row.today_completed),
    }));

    if (byCurrency.length === 1) {
      return {
        currency: byCurrency[0].currency,
        todayBooked: byCurrency[0].todayBooked,
        todayCompleted: byCurrency[0].todayCompleted,
        byCurrency,
      };
    }

    return {
      currency: 'MULTIPLE',
      todayBooked: null,
      todayCompleted: null,
      byCurrency,
    };
  }

  async getMetrics() {
    const range = this.serviceDayRange();
    const nowText = this.now().toISOString().slice(0, 19).replace('T', ' ');
    const [booking, driver, settlement, revenueRows] = await Promise.all([
      this.repository.getBookingMetrics(range),
      this.repository.getDriverMetrics(),
      this.repository.getSettlementMetrics(nowText),
      this.repository.getRevenueByCurrency(range),
    ]);

    const data = {
      date: range.date,
      timezone: TIMEZONE,
      bookings: {
        today: this.number(booking.today),
        pending: this.number(booking.pending),
        unassigned: this.number(booking.unassigned),
        assigned: this.number(booking.assigned),
        onRoute: this.number(booking.on_route),
        arrived: this.number(booking.arrived),
        completed: this.number(booking.completed),
        cancelled: this.number(booking.cancelled),
        noShow: this.number(booking.no_show),
      },
      drivers: {
        online: this.number(driver.online),
        activeJobs: this.number(driver.active_jobs),
      },
      settlements: {
        pending: this.number(settlement.pending),
        overdue: this.number(settlement.overdue),
      },
      revenue: this.mapRevenue(revenueRows),
      updatedAt: this.now().toISOString(),
    };

    logger.info('Admin dashboard metrics loaded', {
      date: data.date,
      timezone: data.timezone,
    });
    return data;
  }
}

module.exports = AdminDashboardService;
