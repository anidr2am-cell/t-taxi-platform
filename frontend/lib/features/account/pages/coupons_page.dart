import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/services/auth_token_storage.dart';
import '../../auth/widgets/booking_social_login_section.dart';
import '../services/coupon_api_service.dart';
import '../widgets/customer_coupon_image.dart';

class CouponsPage extends StatefulWidget {
  const CouponsPage({super.key, this.couponApiService});

  final CouponApiService? couponApiService;

  @override
  State<CouponsPage> createState() => _CouponsPageState();
}

class _CouponsPageState extends State<CouponsPage> {
  bool _loading = true;
  String? _errorMessage;
  List<CustomerCouponItem> _coupons = const [];
  String? _accessToken;

  CouponApiService _resolveApiService() {
    return widget.couponApiService ??
        CouponApiService(session: AuthScope.of(context).customerSession);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCoupons();
    });
  }

  Future<void> _loadCoupons() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final api = _resolveApiService();
      final session = await AuthTokenStorage().loadSession();
      final coupons = await api.listCoupons();
      if (!mounted) return;
      setState(() {
        _coupons = coupons;
        _accessToken = session?.accessToken;
        _loading = false;
      });
    } on CouponApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = context.l10n.t('account_coupons_load_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final authController = AuthScope.of(context);
    final available = _coupons.where((item) => item.isAvailable).toList();
    final used = _coupons.where((item) => !item.isAvailable).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('account_coupons_title'))),
      body: AppUi.centeredContent(
        child: ListView(
          padding: AppUi.pagePadding(context),
          children: [
            if (!authController.isLoggedIn)
              AppUi.surfaceCard(
                child: Text(l10n.t('account_sign_in_required')),
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppTokens.spaceXl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              AppUi.surfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_errorMessage!),
                    const SizedBox(height: AppTokens.spaceMd),
                    FilledButton(
                      onPressed: _loadCoupons,
                      child: Text(l10n.t('account_mileage_retry')),
                    ),
                  ],
                ),
              )
            else ...[
              AppUi.sectionHeader(
                context,
                title: l10n.t('account_coupons_available_section'),
              ),
              if (available.isEmpty)
                AppUi.surfaceCard(
                  child: Text(l10n.t('account_coupons_empty_available')),
                )
              else
                ...available.map((coupon) => _CouponTile(
                      coupon: coupon,
                      l10n: l10n,
                      muted: false,
                      accessToken: _accessToken,
                    )),
              const SizedBox(height: AppTokens.spaceLg),
              AppUi.sectionHeader(
                context,
                title: l10n.t('account_coupons_used_section'),
              ),
              if (used.isEmpty)
                AppUi.surfaceCard(
                  child: Text(l10n.t('account_coupons_empty_used')),
                )
              else
                ...used.map((coupon) => _CouponTile(
                      coupon: coupon,
                      l10n: l10n,
                      muted: true,
                      accessToken: _accessToken,
                    )),
            ],
          ],
        ),
      ),
    );
  }
}

class _CouponTile extends StatelessWidget {
  const _CouponTile({
    required this.coupon,
    required this.l10n,
    required this.muted,
    this.accessToken,
  });

  final CustomerCouponItem coupon;
  final AppLocalizations l10n;
  final bool muted;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final textColor = muted ? AppTokens.textSecondary : AppTokens.textPrimary;
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppTokens.textSecondary,
        );
    final showImage = coupon.imageUrl != null &&
        coupon.imageUrl!.isNotEmpty &&
        accessToken != null &&
        accessToken!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: AppUi.surfaceCard(
        child: Opacity(
          opacity: muted ? 0.72 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showImage) ...[
                CustomerCouponImage(
                  imageUrl: coupon.imageUrl!,
                  accessToken: accessToken!,
                ),
                const SizedBox(height: AppTokens.spaceSm),
              ],
              Text(
                coupon.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AppTokens.spaceXs),
              Text(
                '${coupon.discountAmount} ${l10n.t('thb')}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: muted ? AppTokens.textSecondary : AppTokens.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (coupon.issuedAt != null && coupon.isAvailable) ...[
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  '${l10n.t('account_coupons_issued_at')}: ${coupon.issuedAt!}',
                  style: subtitleStyle,
                ),
              ],
              if (coupon.usedAt != null && !coupon.isAvailable) ...[
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  '${l10n.t('account_coupons_used_at')}: ${coupon.usedAt!}',
                  style: subtitleStyle,
                ),
              ],
              if (coupon.bookingNumber != null && !coupon.isAvailable) ...[
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  '${l10n.t('account_coupons_used_booking')}: ${coupon.bookingNumber!}',
                  style: subtitleStyle,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
