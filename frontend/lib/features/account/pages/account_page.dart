import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/auth_user.dart';
import '../../auth/widgets/booking_social_login_section.dart';
import '../services/mileage_api_service.dart';
import '../utils/auth_provider_display.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    this.mileageApiService,
    this.authController,
  });

  final MileageApiService? mileageApiService;
  final AuthController? authController;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late final MileageApiService _mileageApiService =
      widget.mileageApiService ?? MileageApiService();

  bool _loadingMileage = true;
  int? _mileageBalance;
  String? _mileageError;

  AuthController _resolveController(BuildContext context) {
    return widget.authController ?? AuthScope.of(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMileageIfLoggedIn();
    });
  }

  Future<void> _loadMileageIfLoggedIn() async {
    final controller = _resolveController(context);
    if (!controller.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loadingMileage = false;
        _mileageBalance = null;
        _mileageError = null;
      });
      return;
    }

    setState(() {
      _loadingMileage = true;
      _mileageError = null;
    });

    try {
      final result = await _mileageApiService.getMileageBalance();
      if (!mounted) return;
      setState(() {
        _mileageBalance = result.balance;
        _loadingMileage = false;
      });
    } on MileageApiException catch (error) {
      if (!mounted) return;
      final authController = _resolveController(context);
      if (await authController.handleUnauthorizedApi(error)) {
        setState(() {
          _loadingMileage = false;
          _mileageError = context.l10n.t('account_mileage_load_failed');
        });
        return;
      }
      setState(() {
        _loadingMileage = false;
        _mileageError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMileage = false;
        _mileageError = context.l10n.t('account_mileage_load_failed');
      });
    }
  }

  Future<void> _handleLogout(AuthController controller) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('account_logout_menu')),
        content: Text(l10n.t('account_logout_confirm_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('account_logout_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('account_logout_menu')),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await controller.signOut();
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final message = l10n.t('landing_header_logout_success');
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _resolveController(context);
    final l10n = context.l10n;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isInitialized) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.t('account_page_title'))),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!controller.isLoggedIn) {
          return Scaffold(
            key: const Key('account_page_signed_out'),
            appBar: AppBar(title: Text(l10n.t('account_page_title'))),
            body: Center(
              child: Padding(
                padding: AppUi.pagePadding(context),
                child: Text(
                  l10n.t('account_sign_in_required'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final user = controller.user!;

        return Scaffold(
          key: const Key('account_page'),
          appBar: AppBar(title: Text(l10n.t('account_page_title'))),
          body: ListView(
            padding: AppUi.pagePadding(context),
            children: [
              _ProfileHeader(user: user, l10n: l10n),
              const SizedBox(height: AppTokens.spaceMd),
              _MileageCard(
                l10n: l10n,
                loading: _loadingMileage,
                balance: _mileageBalance,
                errorMessage: _mileageError,
                onRetry: _loadMileageIfLoggedIn,
              ),
              const SizedBox(height: AppTokens.spaceLg),
              AppUi.sectionHeader(
                context,
                title: l10n.t('account_menu_section_title'),
              ),
              AppUi.surfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      key: const Key('account_my_bookings_menu'),
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(l10n.t('account_my_bookings_menu')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.of(context).pushNamed('/my-bookings'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      key: const Key('account_logout_menu'),
                      leading: const Icon(Icons.logout),
                      title: Text(l10n.t('account_logout_menu')),
                      onTap: controller.isLoading
                          ? null
                          : () => _handleLogout(controller),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.l10n});

  final AuthUser user;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final providerLabel = AuthProviderDisplay.labelForProvider(
      l10n,
      user.authProvider,
    );

    return AppUi.surfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTokens.primary.withValues(alpha: 0.12),
            child: const Icon(Icons.person, color: AppTokens.primary),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (user.email != null && user.email!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    user.email!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (providerLabel != null) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Container(
                    key: const Key('account_auth_provider_badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.surfaceMuted,
                      borderRadius: AppTokens.borderRadiusMd,
                      border: Border.all(color: AppTokens.border),
                    ),
                    child: Text(
                      providerLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MileageCard extends StatelessWidget {
  const _MileageCard({
    required this.l10n,
    required this.loading,
    required this.balance,
    required this.errorMessage,
    required this.onRetry,
  });

  final AppLocalizations l10n;
  final bool loading;
  final int? balance;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('account_mileage_card'),
      child: AppUi.surfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('account_mileage_label'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            if (loading)
              Row(
                key: const Key('account_mileage_loading'),
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  Text(
                    l10n.t('account_mileage_loading'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              )
            else if (errorMessage != null)
              Row(
                key: const Key('account_mileage_error'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      l10n.t('account_mileage_load_failed'),
                      style: const TextStyle(color: AppTokens.error),
                    ),
                  ),
                  TextButton(
                    onPressed: onRetry,
                    child: Text(l10n.t('account_mileage_retry')),
                  ),
                ],
              )
            else
              KeyedSubtree(
                key: const Key('account_mileage_balance'),
                child: Text(
                  l10n
                      .t('account_mileage_balance')
                      .replaceAll(
                        '{balance}',
                        AuthProviderDisplay.formatPoints(balance ?? 0),
                      ),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTokens.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
