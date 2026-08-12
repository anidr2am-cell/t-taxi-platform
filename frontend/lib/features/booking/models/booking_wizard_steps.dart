/// Semantic step indices for the 5-step T-Rider booking wizard.
abstract final class BookingWizardSteps {
  static const route = 0;
  static const schedule = 1;
  static const vehicle = 2;
  static const customer = 3;
  static const review = 4;

  static const stepCount = 5;

  static const validationSteps = [route, schedule, vehicle, customer, review];
  static const preConfirmationSteps = [route, schedule, vehicle, customer];

  static String titleKey(int step) {
    switch (step) {
      case route:
        return 'wizard_step_route_title';
      case schedule:
        return 'wizard_step_schedule_title';
      case vehicle:
        return 'wizard_step_vehicle_title';
      case customer:
        return 'wizard_step_customer_title';
      case review:
        return 'wizard_step_review_title';
      default:
        return 'book_your_ride';
    }
  }

  /// Maps persisted 8-step wizard indices to the 5-step model.
  static int migrateLegacyStep(int step) {
    if (step <= 2) return route;
    if (step == 3) return schedule;
    if (step <= 5) return vehicle;
    if (step == 6) return customer;
    return review;
  }

  static int clampStep(int step) {
    if (step < 0) return route;
    if (step >= stepCount) return review;
    return step;
  }

  static String analyticsName(int step) {
    switch (step) {
      case route:
        return 'route';
      case schedule:
        return 'schedule';
      case vehicle:
        return 'vehicle';
      case customer:
        return 'customer';
      case review:
        return 'review';
      default:
        return 'unknown';
    }
  }
}
