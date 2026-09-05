import 'dart:async';

import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../services/home_banner_api_service.dart';
import 'landing_hero.dart';

/// Layout constants for the landing hero carousel [AspectRatio] frame.
///
/// Flutter [AspectRatio.aspectRatio] is width / height. The carousel applies
/// 16px horizontal margin on each side, so the aspect ratio width is
/// `viewportWidth - 32`, not the full viewport width.
abstract final class LandingHeroCarouselLayout {
  static const carouselHorizontalMargin = 32.0;

  static const mobileReferenceViewportWidth = 360.0;
  /// ~57% of the legacy 520px hero; fits promo banners at 328px content width.
  static const mobileReferenceHeroHeight = 300.0;

  static const desktopReferenceViewportWidth = 1100.0;
  /// Target ~388px (57% of legacy 680). Not used while [LandingBookingWidget]
  /// overflows the shorter frame (~269px); kept for banner-aspect reference.
  static const desktopHeroHeightWithBookingWidgetTarget = 388.0;
  /// ~57% of legacy 480px — used when no desktop booking widget is shown.
  static const desktopHeroHeightWithoutBookingWidget = 274.0;
  /// Legacy desktop frame height when the booking widget is present.
  static const desktopHeroHeightWithBookingWidget = 680.0;

  /// 360px viewport − 32px margin → 328px content width → 328 / 300 ≈ 1.093.
  static double get mobileAspectRatio =>
      (mobileReferenceViewportWidth - carouselHorizontalMargin) /
      mobileReferenceHeroHeight;

  static double desktopAspectRatio({required bool hasDesktopBookingWidget}) {
    final referenceContentWidth =
        desktopReferenceViewportWidth - carouselHorizontalMargin;
    final referenceHeight = hasDesktopBookingWidget
        ? desktopHeroHeightWithBookingWidget
        : desktopHeroHeightWithoutBookingWidget;
    return referenceContentWidth / referenceHeight;
  }
}

class LandingHeroCarousel extends StatefulWidget {
  const LandingHeroCarousel({
    super.key,
    required this.onBook,
    this.desktopBookingWidget,
    this.homeBannerApiService,
    this.initialBanners,
    @visibleForTesting this.testBannerAssetPath,
  });

  final VoidCallback onBook;
  final Widget? desktopBookingWidget;
  final HomeBannerApiService? homeBannerApiService;
  final List<HomeBannerItem>? initialBanners;

  /// When set (widget tests only), promo slides render this asset instead of network URLs.
  @visibleForTesting
  final String? testBannerAssetPath;

  @override
  State<LandingHeroCarousel> createState() => _LandingHeroCarouselState();
}

class _LandingHeroCarouselState extends State<LandingHeroCarousel> {
  final _pageController = PageController();
  Timer? _autoSlideTimer;
  List<HomeBannerItem> _banners = const [];
  int _currentPage = 0;
  bool _loadingBanners = true;

  HomeBannerApiService get _api =>
      widget.homeBannerApiService ?? HomeBannerApiService();

  int get _pageCount => 1 + _banners.length;

  @override
  void initState() {
    super.initState();
    _loadBanners();
    _startAutoSlide();
  }

  @override
  void didUpdateWidget(covariant LandingHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialBanners != widget.initialBanners) {
      _applyInitialBanners();
    }
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadBanners() async {
    if (widget.initialBanners != null) {
      _applyInitialBanners();
      return;
    }
    try {
      final banners = await _api.listActiveBanners();
      if (!mounted) return;
      setState(() {
        _banners = banners;
        _loadingBanners = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingBanners = false);
    }
  }

  void _applyInitialBanners() {
    setState(() {
      _banners = widget.initialBanners ?? const [];
      _loadingBanners = false;
    });
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_pageController.hasClients || _pageCount <= 1) return;
      final nextPage = (_currentPage + 1) % _pageCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
  }

  /// Width / height for the carousel frame (see [LandingHeroCarouselLayout]).
  double _carouselAspectRatio(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) {
      return LandingHeroCarouselLayout.desktopAspectRatio(
        hasDesktopBookingWidget: widget.desktopBookingWidget != null,
      );
    }
    return LandingHeroCarouselLayout.mobileAspectRatio;
  }

  @override
  Widget build(BuildContext context) {
    final showIndicators = _pageCount > 1;

    return Container(
      key: const Key('landing_hero_carousel'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: _carouselAspectRatio(context),
            child: ClipRRect(
              borderRadius: AppTokens.borderRadiusLg,
              child: _loadingBanners && widget.initialBanners == null
                  ? const Center(child: CircularProgressIndicator())
                  : PageView.builder(
                      controller: _pageController,
                      itemCount: _pageCount,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return LandingHero(
                            onBook: widget.onBook,
                            desktopBookingWidget: widget.desktopBookingWidget,
                            embeddedInCarousel: true,
                          );
                        }
                        final banner = _banners[index - 1];
                        return _PromoBannerSlide(
                          banner: banner,
                          onTap: widget.onBook,
                          testAssetPath: widget.testBannerAssetPath,
                        );
                      },
                    ),
            ),
          ),
          if (showIndicators) ...[
            const SizedBox(height: 8),
            _PageIndicator(
              count: _pageCount,
              currentIndex: _currentPage,
            ),
          ],
        ],
      ),
    );
  }
}

class _PromoBannerSlide extends StatelessWidget {
  const _PromoBannerSlide({
    required this.banner,
    required this.onTap,
    this.testAssetPath,
  });

  final HomeBannerItem banner;
  final VoidCallback onTap;
  final String? testAssetPath;

  @override
  Widget build(BuildContext context) {
    final image = testAssetPath != null
        ? Image.asset(
            testAssetPath!,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          )
        : Image.network(
            banner.resolveImageUrl(),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: AppTokens.surface,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              );
            },
          );

    return Semantics(
      button: true,
      label: 'Promotional banner',
      child: Material(
        key: Key('landing_promo_banner_${banner.id}'),
        color: AppTokens.surface,
        child: InkWell(
          onTap: onTap,
          child: ColoredBox(
            color: AppTokens.surface,
            child: Center(child: image),
          ),
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.count,
    required this.currentIndex,
  });

  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 10 : 7,
          height: active ? 10 : 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppTokens.primary : AppTokens.border,
          ),
        );
      }),
    );
  }
}
