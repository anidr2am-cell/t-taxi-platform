import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../utils/pickup_time_format.dart';
import 'wizard_compact.dart';

class PickupTimePickerSheet extends StatefulWidget {
  final int initialHour24;
  final int initialMinute;

  const PickupTimePickerSheet({
    super.key,
    required this.initialHour24,
    required this.initialMinute,
  });

  static Future<({int hour24, int minute})?> show(
    BuildContext context, {
    required int initialHour24,
    required int initialMinute,
  }) {
    return showModalBottomSheet<({int hour24, int minute})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PickupTimePickerSheet(
        initialHour24: initialHour24,
        initialMinute: initialMinute,
      ),
    );
  }

  @override
  State<PickupTimePickerSheet> createState() => _PickupTimePickerSheetState();
}

class _PickupTimePickerSheetState extends State<PickupTimePickerSheet> {
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late bool _pm;
  late int _hour12;
  late int _minute;
  late final TextEditingController _manualController;
  String? _manualErrorKey;

  @override
  void initState() {
    super.initState();
    _pm = PickupTimeFormat.isPm(widget.initialHour24);
    _hour12 = PickupTimeFormat.hour12From24(widget.initialHour24);
    _minute = widget.initialMinute;
    _hourController = FixedExtentScrollController(initialItem: _hour12 - 1);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
    _manualController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _manualController.text = _displayValue(context);
  }

  String _displayValue(BuildContext context) {
    final l10n = context.l10n;
    return PickupTimeFormat.formatDisplay(
      hour24: _currentHour24(),
      minute: _currentMinute(),
      amLabel: l10n.t('pickup_time_am'),
      pmLabel: l10n.t('pickup_time_pm'),
    );
  }

  int _currentHour24() {
    return PickupTimeFormat.hour24From12(hour12: _hour12, pm: _pm);
  }

  int _currentMinute() => _minute;

  void _syncManualField() {
    _manualController.text = _displayValue(context);
    _manualErrorKey = null;
  }

  void _applyManualInput() {
    final l10n = context.l10n;
    final parsed = PickupTimeFormat.parseManualInput(
      _manualController.text,
      amLabel: l10n.t('pickup_time_am'),
      pmLabel: l10n.t('pickup_time_pm'),
    );
    if (parsed == null) {
      setState(() => _manualErrorKey = 'pickup_time_invalid');
      return;
    }
    setState(() {
      _pm = PickupTimeFormat.isPm(parsed.hour24);
      _hour12 = PickupTimeFormat.hour12From24(parsed.hour24);
      _minute = parsed.minute;
      _hourController.jumpToItem(_hour12 - 1);
      _minuteController.jumpToItem(_minute);
      _manualErrorKey = null;
      _manualController.text = _displayValue(context);
    });
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.t('pickup_time_select'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    (hour24: _currentHour24(), minute: _currentMinute()),
                  ),
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: _hourController,
                      itemExtent: 36,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _hour12 = index + 1;
                          _syncManualField();
                        });
                      },
                      children: List.generate(
                        12,
                        (index) => Center(
                          child: Text('${index + 1}'.padLeft(2, '0')),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: _minuteController,
                      itemExtent: 36,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _minute = PickupTimeFormat.minuteOptions[index];
                          _syncManualField();
                        });
                      },
                      children: PickupTimeFormat.minuteOptions
                          .map(
                            (minute) => Center(
                              child: Text(minute.toString().padLeft(2, '0')),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _PeriodChip(
                          label: l10n.t('pickup_time_am'),
                          selected: !_pm,
                          onTap: () {
                            setState(() {
                              _pm = false;
                              _syncManualField();
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        _PeriodChip(
                          label: l10n.t('pickup_time_pm'),
                          selected: _pm,
                          onTap: () {
                            setState(() {
                              _pm = true;
                              _syncManualField();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('pickup_time_enter_manually'),
              style: WizardCompact.hintTextStyle,
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _manualController,
              decoration: WizardCompact.inputDecoration(
                label: l10n.t('pickup_time'),
                hint: PickupTimeFormat.formatDisplay(
                  hour24: 9,
                  minute: 30,
                  amLabel: l10n.t('pickup_time_am'),
                  pmLabel: l10n.t('pickup_time_pm'),
                ),
              ).copyWith(
                errorText: _manualErrorKey != null ? l10n.t(_manualErrorKey!) : null,
              ),
              onSubmitted: (_) => _applyManualInput(),
              onChanged: (_) {
                if (_manualErrorKey != null) {
                  setState(() => _manualErrorKey = null);
                }
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _applyManualInput,
                child: Text(l10n.t('pickup_time_apply_manual')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusSm,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 72),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTokens.primaryLight : AppTokens.surfaceMuted,
            borderRadius: AppTokens.borderRadiusSm,
            border: Border.all(
              color: selected ? AppTokens.primary : AppTokens.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? AppTokens.primaryDark : AppTokens.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
