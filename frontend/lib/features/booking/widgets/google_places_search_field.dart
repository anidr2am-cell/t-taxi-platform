import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../../utils/user_facing_error.dart';
import '../models/airport_shortcuts.dart';
import '../models/location_option.dart';
import '../models/place_prediction.dart';
import '../services/places_api_service.dart';
import '../services/recent_locations_storage.dart';
import 'wizard_status_views.dart';

import 'wizard_compact.dart';

class GooglePlacesSearchField extends StatefulWidget {
  final String label;
  final LocationOption? selected;
  final String languageCode;
  final bool showAirportShortcuts;
  final bool recentNonAirportOnly;
  final String? airportShortcutsLabelKey;
  final bool compact;
  final FocusNode? focusNode;
  final ValueChanged<LocationOption> onSelected;
  final PlacesApiService? placesApi;

  const GooglePlacesSearchField({
    super.key,
    required this.label,
    required this.languageCode,
    required this.onSelected,
    this.selected,
    this.showAirportShortcuts = false,
    this.recentNonAirportOnly = false,
    this.airportShortcutsLabelKey,
    this.compact = false,
    this.focusNode,
    this.placesApi,
  });

  @override
  State<GooglePlacesSearchField> createState() => _GooglePlacesSearchFieldState();
}

class _GooglePlacesSearchFieldState extends State<GooglePlacesSearchField> {
  late final PlacesApiService _placesApi;
  final _recentStorage = RecentLocationsStorage();
  final _controller = TextEditingController();
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

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
    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode();
    }
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
    _ownedFocusNode?.dispose();
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
        _error = userFacingError(e, fallback: 'ui_load_failed');
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
        _error = userFacingError(e, fallback: 'ui_load_failed');
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
    final isAirport = kind == LocationKind.airport;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isAirport
            ? AppTokens.primary.withValues(alpha: 0.1)
            : AppTokens.accent.withValues(alpha: 0.12),
        borderRadius: AppTokens.borderRadiusSm,
      ),
      child: Icon(
        isAirport ? Icons.flight : Icons.place_outlined,
        color: isAirport ? AppTokens.primary : AppTokens.accent,
        size: 22,
      ),
    );
  }

  List<LocationOption> get _visibleRecents {
    if (!widget.recentNonAirportOnly) return _recentLocations;
    return _recentLocations
        .where((location) => location.kind != LocationKind.airport)
        .toList();
  }

  Widget _airportShortcuts(AppLocalizations l10n) {
    final labelKey = widget.airportShortcutsLabelKey ?? 'airport_shortcuts';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t(labelKey),
          style: const TextStyle(
            fontSize: 13,
            color: AppTokens.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AirportShortcuts.thailandAirports.map((airport) {
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
    final recents = _visibleRecents;
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
    if (recents.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t(
            widget.recentNonAirportOnly
                ? 'recent_non_airport_places'
                : 'recent_locations',
          ),
          style: const TextStyle(
            fontSize: 13,
            color: AppTokens.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...recents.map((location) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppUi.surfaceCard(
              onTap: _loadingDetails ? null : () => _applyLocation(location),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _locationIcon(location.kind),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          location.name ?? location.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (location.address != null && location.address!.isNotEmpty)
                          Text(
                            location.address!,
                            style: const TextStyle(
                              color: AppTokens.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _selectedCard(AppLocalizations l10n) {
    final location = widget.selected!;
    return AppUi.selectedInfoCard(
      title: location.name ?? location.displayName,
      subtitle: location.address,
      meta: location.latitude != null && location.longitude != null
          ? '${location.latitude!.toStringAsFixed(5)}, ${location.longitude!.toStringAsFixed(5)}'
          : null,
      icon: location.kind == LocationKind.airport ? Icons.flight : Icons.place_outlined,
      changeLabel: l10n.t('change_location'),
      onChange: _startEditing,
      loading: _loadingDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (!_editing && widget.selected != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.compact) ...[
            Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
          ],
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
              child: AppUi.errorState(message: l10n.t(_error!)),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.compact) ...[
          Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
        ],
        if (widget.showAirportShortcuts) _airportShortcuts(l10n),
        _recentSection(l10n),
        Focus(
          onKeyEvent: _handleKeyEvent,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: widget.compact
                ? WizardCompact.inputDecoration(
                    label: widget.label,
                    hint: l10n.t('search_place'),
                    prefixIcon: const Icon(Icons.search, size: 20),
                  )
                : InputDecoration(
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
              color: AppTokens.surface,
              borderRadius: AppTokens.borderRadiusMd,
              border: Border.all(color: AppTokens.border),
              boxShadow: AppTokens.cardShadow(),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _predictions.length,
              itemBuilder: (context, index) {
                final item = _predictions[index];
                final highlighted = index == _highlightedIndex;
                return Material(
                  color: highlighted ? AppTokens.primary.withValues(alpha: 0.08) : null,
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
