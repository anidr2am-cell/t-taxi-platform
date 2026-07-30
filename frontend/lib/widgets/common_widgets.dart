import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';

class PlaceSearchField extends StatefulWidget {
  final String label;
  final String? initialValue;
  final String languageCode;
  final ValueChanged<Map<String, String>> onSelected;

  const PlaceSearchField({
    super.key,
    required this.label,
    this.initialValue,
    required this.languageCode,
    required this.onSelected,
  });

  @override
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) _controller.text = widget.initialValue!;
  }

  Future<void> _search(String query) async {
    if (query.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ApiService().placesAutocomplete(
        query,
        widget.languageCode,
      );
      final predictions = result['predictions'] as List? ?? [];
      setState(() {
        _suggestions = predictions
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _selectPlace(String placeId, String description) async {
    _controller.text = description;
    setState(() => _suggestions = []);
    try {
      final result = await ApiService().placeDetails(
        placeId,
        widget.languageCode,
      );
      final resultData = result['result'] as Map<String, dynamic>?;
      final address =
          resultData?['formatted_address'] as String? ?? description;
      widget.onSelected({'placeId': placeId, 'address': address});
    } catch (_) {
      widget.onSelected({'placeId': placeId, 'address': description});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: context.l10n.t('search_place'),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onChanged: _search,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final item = _suggestions[index];
                return ListTile(
                  title: Text(item['description'] as String? ?? ''),
                  onTap: () => _selectPlace(
                    item['place_id'] as String,
                    item['description'] as String,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class CounterRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;

  const CounterRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(
            '$value',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
