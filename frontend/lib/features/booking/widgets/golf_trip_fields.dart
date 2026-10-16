import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../services/api_service.dart';

class GolfTripFields extends StatefulWidget {
  const GolfTripFields({
    super.key,
    required this.value,
    required this.onChanged,
    this.courses,
  });
  final Map<String, dynamic>? value;
  final void Function(Map<String, dynamic> value, Map<String, dynamic>? course)
  onChanged;
  final List<Map<String, dynamic>>? courses;
  @override
  State<GolfTripFields> createState() => _GolfTripFieldsState();
}

class _GolfTripFieldsState extends State<GolfTripFields> {
  List<Map<String, dynamic>> _courses = [];
  bool _loading = true, _failed = false;
  String _search = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items =
          widget.courses ??
          (await ApiService().getGolfCourses())
              .map((x) => Map<String, dynamic>.from(x as Map))
              .toList();
      if (mounted)
        setState(() {
          _courses = items;
          _loading = false;
          _failed = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _failed = true;
        });
    }
  }

  void _change(String key, dynamic value) {
    final selection = {...?widget.value, key: value};
    Map<String, dynamic>? course;
    for (final c in _courses) {
      if (c['id'] == selection['courseId']) course = c;
    }
    widget.onChanged(selection, course);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n.t;
    final language = Localizations.localeOf(context).languageCode;
    String name(Map c) =>
        ((c['names'] as Map?)?[language] ??
                (c['names'] as Map?)?['en'] ??
                c['name'])
            .toString();
    final visible = _courses
        .where(
          (c) =>
              c['id'] == widget.value?['courseId'] ||
              '${c['names']} ${c['name']}'.toLowerCase().contains(
                _search.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('golf_package_included')),
        const SizedBox(height: AppTokens.spaceSm),
        DropdownButtonFormField<String>(
          key: const Key('golfTripType'),
          initialValue: widget.value?['tripType'] as String?,
          isExpanded: true,
          decoration: InputDecoration(labelText: t('golf_trip_type')),
          items: [
            for (final type in ['ROUND_TRIP', 'OUTBOUND', 'RETURN'])
              DropdownMenuItem(value: type, child: Text(t('golf_trip_$type'))),
          ],
          onChanged: (v) => _change('tripType', v),
        ),
        if (widget.value?['tripType'] == 'ROUND_TRIP') ...[
          const SizedBox(height: AppTokens.spaceSm),
          DropdownButtonFormField<int>(
            key: const Key('golfHoles'),
            initialValue: widget.value?['holes'] as int?,
            decoration: InputDecoration(labelText: t('golf_holes')),
            items: [
              for (final h in [18, 27, 36])
                DropdownMenuItem(value: h, child: Text('$h')),
            ],
            onChanged: (v) => _change('holes', v),
          ),
        ],
        const SizedBox(height: AppTokens.spaceSm),
        if (_loading)
          const LinearProgressIndicator()
        else if (_failed)
          TextButton(
            onPressed: _load,
            child: Text(t('pricing_inquiry_required')),
          )
        else ...[
          TextField(
            key: const Key('golfCourseSearch'),
            decoration: InputDecoration(labelText: t('golf_course_search')),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          DropdownButtonFormField<int>(
            key: ValueKey('golf-course-${widget.value?['courseId']}'),
            initialValue: widget.value?['courseId'] as int?,
            isExpanded: true,
            decoration: InputDecoration(labelText: t('golf_course')),
            items: [
              for (final c in visible)
                DropdownMenuItem(
                  value: c['id'] as int,
                  child: Text(name(c), maxLines: 2),
                ),
            ],
            onChanged: (v) => _change('courseId', v),
          ),
        ],
        const SizedBox(height: AppTokens.spaceMd),
      ],
    );
  }
}
