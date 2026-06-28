import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../models/airport_shortcuts.dart';
import '../models/location_option.dart';
import '../models/place_prediction.dart';
import '../services/places_api_service.dart';
import '../services/recent_locations_storage.dart';
import 'wizard_status_views.dart';

class GooglePlacesSearchField extends StatefulWidget {
  final String label;
  final LocationOption? selected;
  final String languageCode;
  final bool showAirportShortcuts;
  final ValueChanged<LocationOption> onSelected;
  final PlacesApiService? placesApi;

  const GooglePlacesSearchField({
    super.key,
    required this.label,
    required this.languageCode,
    required this.onSelected,
    this.selected,
    this.showAirportShortcuts = false,
    this.placesApi,
  });

  @override
  State<GooglePlacesSearchField> createState() => _GooglePlacesSearchFieldState();
}

class _GooglePlacesSearchFieldState extends State<GooglePlacesSearchField> {
  late final PlacesApiService _placesApi;
  final _recentStorage = RecentLocationsStorage();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  Timer? _debounce;
  List<PlacePrediction> _predictions = [];
  List<LocationOption> _recentLocations = [];
  bool _loading = false;
  bool _loadingDetails = false;
  bool _loadingRecents = false;
  String? _error;
  bool _editing = false;
  int _highlightedIndex = 0;

  @override
  void initState() {
    super.initState();
    _placesApi = widget.placesApi ?? PlacesApiService();
    _editing = widget.selected == null;
    if (widget.selected != null) {
      _controller.text = widget.selected!.name ?? widget.selected!.displayName;
    }
    _loadRecents();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    setState(() => _loadingRecents = true);
    try {
      final items = await _recentStorage.load();
      setState(() {
        _recentLocations = items;
        _loadingRecents = false;
      });
    } catch (_) {
      setState(() => _loadingRecents = false);
    }
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _predictions = [];
      _error = null;
      _controller.clear();
    });
    _loadRecents();
    _focusNode.requestFocus();
  }

  void _applyLocation(LocationOption location) {
    widget.onSelected(location);
    setState(() {
      _loadingDetails = false;
      _editing = false;
      _predictions = [];
      _controller.text = location.name ?? location.displayName;
    });
    _focusNode.unfocus();
    _loadRecents();
  }

  void _selectShortcut(LocationOption airport) {
    setState(() {
      _error = null;
      _predictions = [];
    });
    _applyLocation(airport);
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _predictions = [];
        _error = null;
        _loading = false;
        _highlightedIndex = 0;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () => _fetchPredictions(query));
  }

  Future<void> _fetchPredictions(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await _placesApi.autocomplete(
        input: query,
        language: widget.languageCode,
      );
      setState(() {
        _predictions = results;
        _loading = false;
        _highlightedIndex = 0;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
        _predictions = [];
      });
    }
  }

  Future<void> _selectPrediction(PlacePrediction prediction) async {
    setState(() {
      _loadingDetails = true;
      _error = null;
      _predictions = [];
    });

    try {
      final details = await _placesApi.getPlaceDetails(
        placeId: prediction.placeId,
        language: widget.languageCode,
      );
      _applyLocation(LocationOption.fromPlaceDetails(details));
    } catch (e) {
      setState(() {
        _loadingDetails = false;
        _error = e.toString();
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _predictions.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1) % _predictions.length;
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex = (_highlightedIndex - 1) % _predictions.length;
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _selectPrediction(_predictions[_highlightedIndex]);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _locationIcon(LocationKind kind) {
    if (kind == LocationKind.airport) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.flight, color: Colors.blue.shade700, size: 22),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.place, color: Colors.red.shade700, size: 22),
    );
  }

  Widget _airportShortcuts(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('airport_shortcuts'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AirportShortcuts.all.map((airport) {
            return OutlinedButton(
              onPressed: _loadingDetails ? null : () => _selectShortcut(airport),
              child: Text(airport.code ?? airport.displayName),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _recentSection(AppLocalizations l10n) {
    if (_loadingRecents) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_recentLocations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('recent_locations'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ..._recentLocations.map((location) {
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: _locationIcon(location.kind),
              title: Text(
                location.name ?? location.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: location.address != null && location.address!.isNotEmpty
                  ? Text(location.address!)
                  : null,
              onTap: _loadingDetails ? null : () => _applyLocation(location),
            ),
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _selectedCard(AppLocalizations l10n) {
    final location = widget.selected!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _locationIcon(location.kind),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    location.name ?? location.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  if (location.address != null && location.address!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      location.address!,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                  if (location.latitude != null && location.longitude != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${location.latitude!.toStringAsFixed(5)}, ${location.longitude!.toStringAsFixed(5)}',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            TextButton(
              onPressed: _loadingDetails ? null : _startEditing,
              child: Text(l10n.t('change_location')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (!_editing && widget.selected != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_loadingDetails)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: WizardLoadingView(message: l10n.t('loading_place_details')),
            )
          else
            _selectedCard(l10n),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (widget.showAirportShortcuts) _airportShortcuts(l10n),
        _recentSection(l10n),
        Focus(
          onKeyEvent: _handleKeyEvent,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              hintText: l10n.t('search_place'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _loading || _loadingDetails
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
            onChanged: _onQueryChanged,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: WizardErrorView(
              message: _error!,
              onRetry: _controller.text.length >= 2
                  ? () => _fetchPredictions(_controller.text)
                  : null,
            ),
          ),
        if (!_loading &&
            _controller.text.trim().length >= 2 &&
            _predictions.isEmpty &&
            _error == null &&
            !_loadingDetails)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: WizardEmptyView(message: l10n.t('no_results')),
          ),
        if (_predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _predictions.length,
              itemBuilder: (context, index) {
                final item = _predictions[index];
                final highlighted = index == _highlightedIndex;
                return Material(
                  color: highlighted ? AppTheme.primary.withValues(alpha: 0.08) : null,
                  child: ListTile(
                    leading: _locationIcon(LocationKind.place),
                    title: Text(
                      item.mainText,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: item.secondaryText.isNotEmpty
                        ? Text(item.secondaryText)
                        : null,
                    onTap: () => _selectPrediction(item),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
