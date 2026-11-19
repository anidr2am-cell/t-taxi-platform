import 'package:flutter/widgets.dart';

class BookingSearchMetadata {
  const BookingSearchMetadata({required this.title, required this.description});

  final String title;
  final String description;

  static BookingSearchMetadata? forPage(String languageCode, String route) {
    if (languageCode != 'ja' || Uri.tryParse(route)?.path != '/booking') {
      return null;
    }
    return const BookingSearchMetadata(
      title: 'タイの空港送迎・パタヤのタクシー予約 | TRider',
      description:
          'タイのスワンナプーム・ドンムアン空港送迎、パタヤのゴルフ場や観光地への移動をオンラインで予約。'
          '出発地・目的地、人数と荷物を入力し、最終料金と含まれるサービスをご確認ください。',
    );
  }
}

/// Keeps search copy in sync with navigation and the selected UI language.
/// It only observes routes; it never changes a route, query, or booking state.
class BookingSearchMetadataObserver extends NavigatorObserver {
  BookingSearchMetadataObserver({
    required String initialPath,
    required this.onMetadataChanged,
  }) : _route = initialPath;

  final void Function(BookingSearchMetadata?) onMetadataChanged;
  String _route;
  String _languageCode = '';
  Route<dynamic>? _currentRoute;

  BookingSearchMetadata? get metadata =>
      BookingSearchMetadata.forPage(_languageCode, _route);

  void setLanguage(String languageCode) {
    if (_languageCode == languageCode) return;
    _languageCode = languageCode;
    onMetadataChanged(metadata);
  }

  void _show(Route<dynamic>? route) {
    _currentRoute = route;
    _route = route?.settings.name ?? '';
    onMetadataChanged(metadata);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _show(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == _currentRoute) _show(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == _currentRoute) _show(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == _currentRoute) _show(previousRoute);
  }
}
