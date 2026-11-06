import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../config/app_config.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import 'preferred_support_button.dart';

class CustomerBookingEditApi {
  CustomerBookingEditApi({http.Client? client, String? baseUrl})
    : client = client ?? http.Client(),
      baseUrl = baseUrl ?? AppConfig.apiBaseUrl;
  final http.Client client;
  final String baseUrl;
  Future<Map<String, dynamic>> request(
    String number,
    String guest,
    String? customer, {
    Map<String, dynamic>? body,
  }) async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (guest.isNotEmpty) 'X-Guest-Access-Token': guest,
      if (guest.isEmpty && customer?.isNotEmpty == true)
        'Authorization': 'Bearer $customer',
    };
    final uri = Uri.parse('$baseUrl/api/v1/bookings/$number/customer-edit');
    final response =
        await (body == null
                ? client.get(uri, headers: headers)
                : client.patch(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 15));
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw Exception('VOUCHER_EDIT_ERROR');
    }
    if (response.statusCode >= 400)
      throw Exception(
        decoded is Map
            ? decoded['error_code'] ?? 'VOUCHER_EDIT_ERROR'
            : 'VOUCHER_EDIT_ERROR',
      );
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }
}

class CustomerBookingEditCard extends StatefulWidget {
  const CustomerBookingEditCard({
    super.key,
    required this.bookingNumber,
    required this.guestToken,
    required this.status,
    this.customerToken,
    required this.onSaved,
    this.api,
  });
  final String bookingNumber, guestToken, status;
  final String? customerToken;
  final Future<void> Function(Map<String, dynamic>) onSaved;
  final CustomerBookingEditApi? api;
  @override
  State<CustomerBookingEditCard> createState() =>
      _CustomerBookingEditCardState();
}

class _CustomerBookingEditCardState extends State<CustomerBookingEditCard> {
  late final api = widget.api ?? CustomerBookingEditApi();
  bool loading = false;
  String? error;
  @override
  void dispose() {
    if (widget.api == null) api.client.close();
    super.dispose();
  }

  Future<void> open() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await api.request(
        widget.bookingNumber,
        widget.guestToken,
        widget.customerToken,
      );
      if (!mounted) return;
      if (data['canEdit'] != true) {
        setState(() => error = context.l10n.t('voucher_edit_closed'));
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (_) => _EditDialog(
          data: data,
          api: api,
          number: widget.bookingNumber,
          guest: widget.guestToken,
          customer: widget.customerToken,
          onSaved: widget.onSaved,
        ),
      );
    } catch (e) {
      if (mounted)
        setState(
          () => error = context.l10n.t(
            e.toString().contains('BOOKING_NOT_ACCESSIBLE')
                ? 'voucher_edit_auth_error'
                : 'voucher_edit_error',
          ),
        );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!const [
          'PENDING',
          'OPEN',
          'CONFIRMED',
          'DRIVER_ASSIGNED',
          'ON_ROUTE',
          'DRIVER_ARRIVED',
        ].contains(widget.status) ||
        widget.guestToken.isEmpty && widget.customerToken?.isNotEmpty != true)
      return const SizedBox.shrink();
    final l = context.l10n;
    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.t('voucher_edit_help')),
          const SizedBox(height: AppTokens.spaceSm),
          OutlinedButton.icon(
            key: const Key('voucherEditOpen'),
            onPressed: loading ? null : open,
            icon: const Icon(Icons.edit_outlined),
            label: Text(l.t('voucher_edit_open')),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: AppTokens.error)),
        ],
      ),
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.data,
    required this.api,
    required this.number,
    required this.guest,
    required this.customer,
    required this.onSaved,
  });
  final Map<String, dynamic> data;
  final CustomerBookingEditApi api;
  final String number, guest;
  final String? customer;
  final Future<void> Function(Map<String, dynamic>) onSaved;
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final form = GlobalKey<FormState>();
  late final phone = TextEditingController(
    text: widget.data['phone'] as String? ?? '',
  );
  late final email = TextEditingController(
    text: widget.data['email'] as String? ?? '',
  );
  late final id = TextEditingController(
    text: widget.data['messengerId'] as String? ?? '',
  );
  late final flight = TextEditingController(
    text: widget.data['flightNumber'] as String? ?? '',
  );
  late final requests = TextEditingController(
    text: widget.data['specialRequests'] as String? ?? '',
  );
  final change = TextEditingController();
  late String? messenger = widget.data['messengerType'] as String?;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    for (final c in [phone, email, id, flight, requests, change]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final data = await widget.api.request(
        widget.number,
        widget.guest,
        widget.customer,
        body: {
          'revision': widget.data['revision'],
          'customer': {
            if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim(),
            'email': email.text.trim().isEmpty ? null : email.text.trim(),
            if (messenger != null) 'messengerType': messenger,
            'messengerId': id.text.trim().isEmpty ? null : id.text.trim(),
          },
          if (widget.data['flightEditable'] == true)
            'flightNumber': flight.text.trim(),
          'specialRequests': requests.text.trim(),
          if (change.text.trim().isNotEmpty)
            'changeRequest': change.text.trim(),
        },
      );
      if (!mounted) return;
      await widget.onSaved(data);
      if (!mounted) return;
      final messengerUi = ScaffoldMessenger.of(context);
      final message = context.l10n.t('voucher_edit_saved');
      Navigator.pop(context);
      messengerUi.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted)
        setState(
          () => error = context.l10n.t(
            e.toString().contains('BOOKING_EDIT_CONFLICT')
                ? 'voucher_edit_conflict'
                : e.toString().contains('BOOKING_EDIT_CLOSED')
                ? 'voucher_edit_closed'
                : 'voucher_edit_error',
          ),
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget field(
      String key,
      TextEditingController c, {
      int lines = 1,
      int? max,
      String? Function(String?)? validator,
      TextInputType? keyboard,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      child: TextFormField(
        key: Key(key),
        controller: c,
        enabled: !saving,
        decoration: InputDecoration(
          labelText: l.t('voucher_edit_$key'),
          alignLabelWithHint: true,
        ),
        minLines: lines,
        maxLines: lines,
        maxLength: max,
        validator: validator,
        keyboardType: keyboard,
      ),
    );
    return Dialog(
      child: SizedBox(
        width: 600,
        height: MediaQuery.sizeOf(context).height * .9,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.t('voucher_edit_title'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: l.t('voucher_edit_close'),
                  ),
                ],
              ),
              Expanded(
                child: Form(
                  key: form,
                  child: ListView(
                    children: [
                      Text(l.t('voucher_edit_help')),
                      const SizedBox(height: AppTokens.spaceMd),
                      field(
                        'phone',
                        phone,
                        keyboard: TextInputType.phone,
                        validator: (v) =>
                            v!.trim().isEmpty &&
                                widget.data['phone'] == null &&
                                messenger == widget.data['messengerType'] &&
                                id.text.trim() ==
                                    (widget.data['messengerId'] ?? '')
                            ? null
                            : RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(v.trim())
                            ? null
                            : l.t('voucher_edit_invalid_phone'),
                      ),
                      field(
                        'email',
                        email,
                        keyboard: TextInputType.emailAddress,
                        validator: (v) =>
                            v!.trim().isEmpty ||
                                RegExp(
                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                ).hasMatch(v.trim())
                            ? null
                            : l.t('voucher_edit_invalid_email'),
                      ),
                      DropdownButtonFormField<String>(
                        key: const Key('voucherEditMessenger'),
                        value: messenger,
                        decoration: InputDecoration(
                          labelText: l.t('voucher_edit_messenger'),
                        ),
                        isExpanded: true,
                        items: [
                          for (final type in [
                            'KAKAO',
                            'LINE',
                            'WHATSAPP',
                            'WECHAT',
                            'TELEGRAM',
                            if (widget.data['messengerType'] == 'SMS') 'SMS',
                          ])
                            DropdownMenuItem(
                              value: type,
                              child: Text(
                                type == 'SMS'
                                    ? l.t('voucher_edit_legacy_sms')
                                    : type,
                              ),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setState(() {
                                if (v != messenger) id.clear();
                                messenger = v;
                              }),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      field(
                        'id',
                        id,
                        max: 100,
                        validator: (v) =>
                            messenger == 'LINE' && v!.trim().isEmpty
                            ? l.t('voucher_edit_required_id')
                            : null,
                      ),
                      if (widget.data['flightEditable'] == true) ...[
                        field('flight', flight, max: 20),
                        Text(l.t('voucher_edit_flight_help')),
                        const SizedBox(height: AppTokens.spaceMd),
                      ],
                      field('requests', requests, lines: 3, max: 2000),
                      Text(
                        l.t('voucher_edit_request_title'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(l.t('voucher_edit_request_help')),
                      const SizedBox(height: AppTokens.spaceMd),
                      field('change_details', change, lines: 3, max: 2000),
                      const PreferredSupportButton(chooseChannel: true),
                      if (error != null)
                        Text(
                          error!,
                          style: const TextStyle(color: AppTokens.error),
                        ),
                    ],
                  ),
                ),
              ),
              FilledButton(
                key: const Key('voucherEditSave'),
                onPressed: saving ? null : save,
                child: Text(
                  l.t('voucher_edit_save'),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
