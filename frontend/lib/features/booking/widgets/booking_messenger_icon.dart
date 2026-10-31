import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../../auth/widgets/social_brand_icons.dart';

/// Shared booking dropdown/support icons. WeChat artwork was owner supplied.
Widget bookingMessengerIcon(String code) => switch (code) {
  'KAKAO' => const KakaoBrandIcon(
    size: 24,
    style: SocialBrandIconStyle.appIcon,
  ),
  'LINE' => const LineBrandIcon(size: 24, style: SocialBrandIconStyle.appIcon),
  'WHATSAPP' => Image.asset(
    'assets/images/brands/whatsapp_app_icon.png',
    width: 24,
    height: 24,
    fit: BoxFit.contain,
  ),
  'WECHAT' => Image.asset(
    'assets/images/brands/wechat_app_icon.png',
    width: 24,
    height: 24,
    fit: BoxFit.contain,
    semanticLabel: 'WeChat',
  ),
  'TELEGRAM' => const Icon(Icons.send_outlined, color: AppTokens.primary),
  _ => const Icon(Icons.chat_outlined, color: AppTokens.primary),
};
