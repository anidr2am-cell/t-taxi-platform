class AdminDashboardMetrics {
  const AdminDashboardMetrics({
    required this.date,
    required this.timezone,
    required this.bookings,
    required this.drivers,
    required this.settlements,
    required this.revenue,
    required this.updatedAt,
  });

  final String date;
  final String timezone;
  final BookingMetrics bookings;
  final DriverMetrics drivers;
  final SettlementMetrics settlements;
  final RevenueMetrics revenue;
  final String updatedAt;

  factory AdminDashboardMetrics.fromJson(Map<String, dynamic> json) {
    return AdminDashboardMetrics(
      date: json['date'] as String? ?? '',
      timezone: json['timezone'] as String? ?? 'Asia/Bangkok',
      bookings: BookingMetrics.fromJson(
        Map<String, dynamic>.from(json['bookings'] as Map? ?? {}),
      ),
      drivers: DriverMetrics.fromJson(
        Map<String, dynamic>.from(json['drivers'] as Map? ?? {}),
      ),
      settlements: SettlementMetrics.fromJson(
        Map<String, dynamic>.from(json['settlements'] as Map? ?? {}),
      ),
      revenue: RevenueMetrics.fromJson(
        Map<String, dynamic>.from(json['revenue'] as Map? ?? {}),
      ),
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class BookingMetrics {
  const BookingMetrics({
    required this.today,
    required this.pending,
    required this.unassigned,
    required this.assigned,
    required this.onRoute,
    required this.arrived,
    required this.completed,
    required this.cancelled,
    required this.noShow,
  });

  final int today;
  final int pending;
  final int unassigned;
  final int assigned;
  final int onRoute;
  final int arrived;
  final int completed;
  final int cancelled;
  final int noShow;

  factory BookingMetrics.fromJson(Map<String, dynamic> json) {
    int value(String key) => (json[key] as num?)?.toInt() ?? 0;
    return BookingMetrics(
      today: value('today'),
      pending: value('pending'),
      unassigned: value('unassigned'),
      assigned: value('assigned'),
      onRoute: value('onRoute'),
      arrived: value('arrived'),
      completed: value('completed'),
      cancelled: value('cancelled'),
      noShow: value('noShow'),
    );
  }
}

class DriverMetrics {
  const DriverMetrics({required this.online, required this.activeJobs});

  final int online;
  final int activeJobs;

  factory DriverMetrics.fromJson(Map<String, dynamic> json) {
    return DriverMetrics(
      online: (json['online'] as num?)?.toInt() ?? 0,
      activeJobs: (json['activeJobs'] as num?)?.toInt() ?? 0,
    );
  }
}

class SettlementMetrics {
  const SettlementMetrics({required this.pending, required this.overdue});

  final int pending;
  final int overdue;

  factory SettlementMetrics.fromJson(Map<String, dynamic> json) {
    return SettlementMetrics(
      pending: (json['pending'] as num?)?.toInt() ?? 0,
      overdue: (json['overdue'] as num?)?.toInt() ?? 0,
    );
  }
}

class RevenueMetrics {
  const RevenueMetrics({
    required this.currency,
    required this.todayBooked,
    required this.todayCompleted,
  });

  final String currency;
  final num? todayBooked;
  final num? todayCompleted;

  factory RevenueMetrics.fromJson(Map<String, dynamic> json) {
    return RevenueMetrics(
      currency: json['currency'] as String? ?? 'THB',
      todayBooked: json['todayBooked'] as num?,
      todayCompleted: json['todayCompleted'] as num?,
    );
  }
}
