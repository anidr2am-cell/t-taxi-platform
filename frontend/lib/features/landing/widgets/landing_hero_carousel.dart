import 'dart:async';

import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../services/home_banner_api_service.dart';
import 'landing_hero.dart';

class LandingHeroCarousel extends StatefulWidget {
  const LandingHeroCarousel({
    super.key,
    required this.onBook,
    this.desktopBookingWidget,
    this.homeBannerApiService,
    this.initialBanners,
  });

  final VoidCallback onBook;
  final Widget? desktopBookingWidget;
  final HomeBannerApiService? homeBannerApiService;
  final List<HomeBannerItem>? initialBanners;

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

  double _carouselHeight(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) {
      return widget.desktopBookingWidget != null ? 680 : 480;
    }
    return 520;
  }

  @override
  Widget build(BuildContext context) {
    final height = _carouselHeight(context);
    final showIndicators = _pageCount > 1;

    return Container(
      key: const Key('landing_hero_carousel'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          SizedBox(
            height: height,
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
                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: LandingHero(
                              onBook: widget.onBook,
                              desktopBookingWidget: widget.desktopBookingWidget,
                              embeddedInCarousel: true,
                            ),
                          );
                        }
                        final banner = _banners[index - 1];
                        return _PromoBannerSlide(
                          banner: banner,
                          onTap: widget.onBook,
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
  });

  final HomeBannerItem banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Promotional banner',
      child: Material(
        key: Key('landing_promo_banner_${banner.id}'),
        color: AppTokens.surfaceMuted,
        child: InkWell(
          onTap: onTap,
          child: Image.network(
            banner.resolveImageUrl(),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: AppTokens.surfaceMuted,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              );
            },
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
