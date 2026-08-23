import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/booking_provider.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/clipboard_writer.dart';
import '../../../widgets/app_ui.dart';
import '../../../widgets/language_selector.dart';
import '../models/booking_contact_connect_args.dart';
import '../models/booking_create_result.dart';
import '../models/contact_channel.dart';
import '../services/booking_analytics.dart';
import '../services/booking_contact_connection_service.dart';
import '../utils/contact_channel_url.dart';
import '../widgets/airport_meeting_guide_card.dart';
import '../widgets/booking_review_form.dart';
import 'booking_complete_page.dart';
import 'urgent_booking_flow_page.dart';

class BookingContactConnectPage extends StatefulWidget {
  const BookingContactConnectPage({
    super.key,
    required this.bookingNumber,
    this.args,
    this.service,
    this.analytics,
  });

  final String bookingNumber;
  final BookingContactConnectArgs? args;
  final BookingContactConnectionService? service;
  final BookingAnalytics? analytics;

  static const pollInterval = Duration(seconds: 5);

  @visibleForTesting
  static String bookingRefMessage(String bookingNumber) =>
      'T-Rider $bookingNumber';

  @override
  State<BookingContactConnectPage> createState() =>
      _BookingContactConnectPageState();
}

class _BookingContactConnectPageState extends State<BookingContactConnectPage>
    with WidgetsBindingObserver {
  late final BookingContactConnectionService _service;
  late final BookingAnalytics _analytics;

  List<ContactChannel> _channels = const [];
  ContactConnectionState? _connection;
  String? _guestToken;
  String? _selectedChannelCode;
  String? _errorMessage;
  bool _loading = true;
  bool _actionBusy = false;
  bool _confirmSubmitting = false;
  bool _isRefreshing = false;
  bool _viewTracked = false;
  Timer? _pollTimer;

  BookingCreateResult? get _result => widget.args?.result;

  bool get _isVerified => _connection?.isVerified ?? false;

  bool get _isConfirmRequested =>
      _connection?.isConfirmRequested ?? false;

  bool get _hasStartedConnection =>
      _selectedChannelCode != null ||
      (_connection?.connectionChannel?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = widget.service ?? BookingContactConnectionService();
    _analytics = widget.analytics ?? BookingAnalytics.instance;
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isConfirmRequested) {
      _refreshConnection();
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final tokenFromResult = _result?.guestAccessToken;
      final token = (tokenFromResult != null && tokenFromResult.isNotEmpty)
          ? tokenFromResult
          : await const BookingReviewApi().loadGuestToken(widget.bookingNumber);

      if (token == null || token.isEmpty) {
        throw BookingContactConnectionException('Guest access token missing');
      }

      if (_result != null) {
        await BookingReviewApi().persistGuestToken(
          widget.bookingNumber,
          token,
        );
      }

      final channelsFuture = _service.getPublicChannels();
      final connectionFuture = _service.getConnection(
        bookingNumber: widget.bookingNumber,
        guestAccessToken: token,
      );
      final channels = await channelsFuture;
      final connection = await connectionFuture;

      if (!mounted) return;
      setState(() {
        _guestToken = token;
        _channels = channels;
        _connection = connection;
        _selectedChannelCode =
            connection.connectionChannel ?? connection.contactChannel;
        _loading = false;
      });

      _trackViewOnce(connection.contactStatus);
      if (connection.isVerified) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _navigateToCompletion(connection: connection, guestToken: token);
        });
        return;
      }
      if (connection.isConfirmRequested) {
        _startPolling();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _trackViewOnce([String? contactStatus]) {
    if (_viewTracked) return;
    _viewTracked = true;
    _analytics.trackContactConnectViewed(
      bookingId: widget.bookingNumber,
      contactStatus: contactStatus ?? _connection?.contactStatus,
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(BookingContactConnectPage.pollInterval, (_) {
      if (_isRefreshing) return;
      _refreshConnection(silent: true);
    });
  }

  Future<void> _refreshConnection({bool silent = false}) async {
    if (_isRefreshing) return;

    final token = _guestToken;
    if (token == null || token.isEmpty) return;

    _isRefreshing = true;
    try {
      final connection = await _service.getConnection(
        bookingNumber: widget.bookingNumber,
        guestAccessToken: token,
      );
      if (!mounted) return;
      setState(() {
        _connection = connection;
        _selectedChannelCode ??=
            connection.connectionChannel ?? connection.contactChannel;
      });
      if (connection.isVerified) {
        _pollTimer?.cancel();
        _navigateToCompletion(connection: connection, guestToken: token);
      }
    } catch (_) {
      if (!silent && mounted) {
        setState(() => _errorMessage = context.l10n.t('contact_connect_load_failed'));
      }
    } finally {
      _isRefreshing = false;
    }
  }

  void _showPageSnackBar(String message) {
    if (!mounted) return;

    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            AppTokens.spaceMd,
            0,
            AppTokens.spaceMd,
            AppTokens.spaceMd + bottomSafe,
          ),
          duration: const Duration(milliseconds: 2000),
        ),
      );
  }

  Future<void> _copyBookingRef() async {
    final l10n = context.l10n;
    final ref = BookingContactConnectPage.bookingRefMessage(
      widget.bookingNumber,
    );
    await writeClipboardText(ref);
    if (!mounted) return;
    _showPageSnackBar(l10n.t('contact_connect_ref_copied'));
  }

  Future<void> _handleChannelTap(ContactChannel channel) async {
    final token = _guestToken;
    if (token == null || _actionBusy) return;

    final ref = BookingContactConnectPage.bookingRefMessage(
      widget.bookingNumber,
    );
    await writeClipboardText(ref);

    if (channel.code == 'WECHAT') {
      setState(() {
        _selectedChannelCode = channel.code;
        _errorMessage = null;
      });
    } else {
      final launched = await _launchChannel(channel, ref);
      if (!launched && mounted) {
        _showPageSnackBar(context.l10n.t('contact_connect_launch_failed'));
      }
    }

    setState(() => _actionBusy = true);
    try {
      final connection = await _service.startConnection(
        bookingNumber: widget.bookingNumber,
        channel: channel.code,
        guestAccessToken: token,
      );
      if (!mounted) return;
      setState(() {
        _connection = connection;
        _selectedChannelCode = channel.code;
        _actionBusy = false;
      });
      _showPageSnackBar(context.l10n.t('contact_connect_ref_copied'));
      _analytics.trackContactConnectStarted(
        bookingId: widget.bookingNumber,
        channel: channel.code,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<bool> _launchChannel(ContactChannel channel, String ref) async {
    Uri? uri;
    switch (channel.code) {
      case 'WHATSAPP':
        final phone = channel.phoneNumber?.replaceAll(RegExp(r'\D'), '') ?? '';
        if (phone.isEmpty) return false;
        uri = parseAllowedContactChannelUrl(
          'https://wa.me/$phone?text=${Uri.encodeComponent(ref)}',
          allowHttp: allowHttpContactUrlsForEnvironment(),
        );
        break;
      case 'LINE':
      case 'KAKAO':
        final url = channel.addUrl?.trim();
        if (url == null || url.isEmpty) return false;
        uri = parseAllowedContactChannelUrl(
          url,
          allowHttp: allowHttpContactUrlsForEnvironment(),
        );
        break;
      default:
        return false;
    }
    if (uri == null) {
      if (mounted) {
        setState(() {
          _errorMessage = context.l10n.t('contact_connect_unsafe_url');
        });
      }
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _confirmSent() async {
    final token = _guestToken;
    if (token == null || _actionBusy) return;

    setState(() {
      _actionBusy = true;
      _confirmSubmitting = true;
    });
    try {
      final connection = await _service.confirmSent(
        bookingNumber: widget.bookingNumber,
        guestAccessToken: token,
      );
      if (!mounted) return;
      setState(() {
        _connection = connection;
        _actionBusy = false;
        _confirmSubmitting = false;
      });
      _analytics.trackContactConfirmRequested(
        bookingId: widget.bookingNumber,
        channel: _selectedChannelCode,
      );
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionBusy = false;
        _confirmSubmitting = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _navigateToCompletion({
    ContactConnectionState? connection,
    String? guestToken,
  }) {
    final args = widget.args;
    final resolvedConnection = connection ?? _connection;
    final token = guestToken ?? _guestToken;
    final result = args?.result ??
        (resolvedConnection != null
            ? resolvedConnection.toMinimalCreateResult(guestAccessToken: token)
            : null);
    if (result == null) {
      Navigator.of(context).pushReplacementNamed('/booking/lookup');
      return;
    }

    switch (resolveContactCompletionTarget(
      args: args,
      connection: resolvedConnection,
      result: result,
    )) {
      case ContactCompletionTarget.lookup:
        Navigator.of(context).pushReplacementNamed('/booking/lookup');
        return;
      case ContactCompletionTarget.urgentFlow:
        _analytics.trackContactConnectSucceeded(bookingId: widget.bookingNumber);
        _analytics.trackBookingFullyCompleted(
          bookingId: widget.bookingNumber,
          vehicleType: args?.selectedVehicle,
          totalPrice: result.totalAmount,
          isUrgent: true,
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => UrgentBookingFlowPage(
              result: result,
              customerPhone: args?.customerPhone,
            ),
          ),
        );
        return;
      case ContactCompletionTarget.completePage:
        _analytics.trackContactConnectSucceeded(bookingId: widget.bookingNumber);
        _analytics.trackBookingFullyCompleted(
          bookingId: widget.bookingNumber,
          vehicleType: args?.selectedVehicle,
          totalPrice: result.totalAmount,
          isUrgent: false,
        );
        if (args == null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => BookingCompletePage(
                result: result,
                serviceLabel: '',
                origin: null,
                destination: null,
                enableCustomerTools: true,
              ),
            ),
          );
          return;
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BookingCompletePage(
              result: result,
              serviceLabel: args.serviceLabel,
              origin: args.origin,
              destination: args.destination,
              review: args.review,
              serviceTypeCode: args.serviceTypeCode,
              originAirportCode: args.originAirportCode,
              nameSignRequested: args.nameSignRequested,
              customerPhone: args.customerPhone,
              scheduledPickupAt: args.scheduledPickupAt,
              selectedVehicle: args.selectedVehicle,
              enableCustomerTools: true,
              meetingVehicleInfo: args.meetingVehicleInfo ??
                  AirportMeetingVehicleInfo(
                    vehicleType: args.selectedVehicle,
                  ),
            ),
          ),
        );
    }
  }

  int get _progressStep {
    if (_isVerified) return 3;
    if (_isConfirmRequested) return 2;
    if (_hasStartedConnection) return 2;
    return 1;
  }

  String get _stepContentKey {
    if (_isConfirmRequested) return 'waiting';
    if (!_hasStartedConnection) return 'channels';
    if (_selectedChannelCode == 'WECHAT') return 'wechat';
    return 'connected';
  }

  Widget _buildStepStatusSection({
    required AppLocalizations l10n,
    required List<ContactChannel> orderedChannels,
    required ContactChannel? selectedChannel,
  }) {
    if (_isConfirmRequested) {
      return _WaitingCard(l10n: l10n);
    }
    if (!_hasStartedConnection) {
      return Column(
        key: const ValueKey('channels'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('contact_connect_choose_channel'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          for (final channel in orderedChannels) ...[
            _ChannelButton(
              channel: channel,
              busy: _actionBusy,
              onTap: () => _handleChannelTap(channel),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: null,
            child: Text(l10n.t('contact_connect_email_soon')),
          ),
        ],
      );
    }
    if (selectedChannel?.code == 'WECHAT') {
      return _WeChatPanel(
        key: const ValueKey('wechat'),
        channel: selectedChannel!,
        l10n: l10n,
        onCopyId: () async {
          final id = selectedChannel.accountId?.trim();
          if (id == null || id.isEmpty) return;
          await writeClipboardText(id);
          if (!context.mounted) return;
          _showPageSnackBar(l10n.t('contact_connect_wechat_id_copied'));
        },
      );
    }
    return KeyedSubtree(
      key: const ValueKey('connected'),
      child: AppUi.surfaceCard(
        backgroundColor: AppTokens.accentLight,
        child: Text(
          l10n.t('contact_connect_after_launch'),
          style: const TextStyle(height: 1.45),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = context.watch<LocaleState>().languageCode;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final showCtaBar = !_loading &&
        !_isConfirmRequested &&
        _hasStartedConnection &&
        !keyboardVisible;
    final orderedChannels = orderContactChannels(_channels, locale);
    final selectedChannel = orderedChannels.cast<ContactChannel?>().firstWhere(
          (channel) => channel!.code == _selectedChannelCode,
          orElse: () => null,
        );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(l10n.t('contact_connect_title')),
        automaticallyImplyLeading: false,
        actions: const [LanguageSelector()],
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProgressSteps(
                        currentStep: _progressStep,
                        l10n: l10n,
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      AppUi.surfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l10n.t('contact_connect_booking_number'),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    widget.bookingNumber,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: l10n.t('booking_number_copy'),
                                  onPressed:
                                      _confirmSubmitting ? null : _copyBookingRef,
                                  icon: const Icon(Icons.copy_outlined),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      Text(
                        l10n.t('contact_connect_intro'),
                        style: const TextStyle(height: 1.5),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      if (_errorMessage != null) ...[
                        AppUi.surfaceCard(
                          backgroundColor: AppTokens.warningLight,
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(height: 1.45),
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceMd),
                      ],
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: KeyedSubtree(
                          key: ValueKey(_stepContentKey),
                          child: _buildStepStatusSection(
                            l10n: l10n,
                            orderedChannels: orderedChannels,
                            selectedChannel: selectedChannel,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_confirmSubmitting)
            Positioned.fill(
              child: ColoredBox(
                key: const Key('contact_connect_confirm_overlay'),
                color: const Color(0x3D000000),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: showCtaBar
          ? Container(
              key: const Key('contact_connect_cta_bar'),
              decoration: const BoxDecoration(
                color: AppTokens.surface,
                border: Border(top: BorderSide(color: AppTokens.border)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 12,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _actionBusy ? null : _confirmSent,
                      child: _actionBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(l10n.t('contact_connect_confirm_sent')),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _ProgressSteps extends StatelessWidget {
  const _ProgressSteps({required this.currentStep, required this.l10n});

  final int currentStep;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final steps = [
      l10n.t('contact_connect_step_created'),
      l10n.t('contact_connect_step_connecting'),
      l10n.t('contact_connect_step_complete'),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: currentStep > i + 1
                    ? AppTokens.primary
                    : AppTokens.border,
              ),
            ),
          Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: currentStep >= i + 1
                    ? AppTokens.primary
                    : AppTokens.border,
                child: currentStep > i + 1
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: currentStep >= i + 1
                              ? Colors.white
                              : AppTokens.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 96,
                child: Text(
                  steps[i],
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ChannelButton extends StatelessWidget {
  const _ChannelButton({
    required this.channel,
    required this.onTap,
    this.busy = false,
  });

  final ContactChannel channel;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: channel.displayName,
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          onPressed: busy ? null : onTap,
          child: Text(channel.displayName),
        ),
      ),
    );
  }
}

class _WeChatPanel extends StatelessWidget {
  const _WeChatPanel({
    super.key,
    required this.channel,
    required this.l10n,
    required this.onCopyId,
  });

  final ContactChannel channel;
  final AppLocalizations l10n;
  final Future<void> Function() onCopyId;

  @override
  Widget build(BuildContext context) {
    final qrUrl = channel.qrImageUrl?.trim();
    final accountId = channel.accountId?.trim();
    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('contact_connect_wechat_title'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.t('contact_connect_wechat_body'),
            style: const TextStyle(height: 1.45),
          ),
          if (qrUrl != null && qrUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            Center(
              child: ClipRRect(
                borderRadius: AppTokens.borderRadiusMd,
                child: Image.network(
                  qrUrl,
                  width: 180,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stackTrace) => const SizedBox(
                    width: 180,
                    height: 180,
                    child: Icon(Icons.qr_code_2, size: 72),
                  ),
                ),
              ),
            ),
          ],
          if (accountId != null && accountId.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    accountId,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                TextButton(
                  onPressed: onCopyId,
                  child: Text(l10n.t('booking_number_copy')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.accentLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.t('contact_connect_waiting'),
                  style: const TextStyle(height: 1.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.t('contact_connect_waiting_hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Resolves [BookingContactConnectPage] from route args or query parameters.
class BookingContactConnectRouteLoader extends StatelessWidget {
  const BookingContactConnectRouteLoader({
    super.key,
    this.uri,
    this.service,
    this.analytics,
  });

  final Uri? uri;
  final BookingContactConnectionService? service;
  final BookingAnalytics? analytics;

  @visibleForTesting
  static String? bookingNumberFromUri(Uri uri) {
    final bookingNumber = uri.queryParameters['bookingNumber']?.trim();
    if (bookingNumber == null || bookingNumber.isEmpty) return null;
    if (!RegExp(r'^TX[0-9A-Za-z_-]+$').hasMatch(bookingNumber)) return null;
    return bookingNumber;
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is BookingContactConnectArgs) {
      return BookingContactConnectPage(
        bookingNumber: args.result.bookingNumber,
        args: args,
        service: service,
        analytics: analytics,
      );
    }

    final resolvedUri = uri ?? Uri.base;
    final bookingNumber = bookingNumberFromUri(resolvedUri);
    if (bookingNumber == null) {
      return Scaffold(
        body: Center(
          child: Text(context.l10n.t('contact_connect_invalid_link')),
        ),
      );
    }

    return BookingContactConnectPage(
      bookingNumber: bookingNumber,
      service: service,
      analytics: analytics,
    );
  }
}
