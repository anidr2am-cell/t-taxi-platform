import 'package:web/web.dart' as web;

import 'booking_search_metadata.dart';

class BookingSearchMetadataBridge {
  static bool _overridden = false;
  static String _previousTitle = '';
  static String? _previousDescription;
  static web.HTMLMetaElement? _description;
  static bool _createdDescription = false;

  static void apply(BookingSearchMetadata? metadata) {
    if (metadata == null) {
      if (!_overridden) return;
      web.document.title = _previousTitle;
      if (_createdDescription) {
        _description?.remove();
      } else {
        _description?.content = _previousDescription ?? '';
      }
      _description = null;
      _overridden = false;
      return;
    }

    if (!_overridden) {
      _previousTitle = web.document.title;
      _description =
          web.document.querySelector('meta[name="description"]')
              as web.HTMLMetaElement?;
      _createdDescription = _description == null;
      _previousDescription = _description?.content;
      if (_createdDescription) {
        _description =
            web.document.createElement('meta') as web.HTMLMetaElement;
        _description!.name = 'description';
        web.document.head?.appendChild(_description!);
      }
      _overridden = true;
    }
    web.document.title = metadata.title;
    _description!.content = metadata.description;
  }
}
