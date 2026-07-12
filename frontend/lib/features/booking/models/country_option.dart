import '../../../l10n/app_localizations.dart';

class CountryOption {
  const CountryOption({
    required this.code,
    required this.en,
    required this.ko,
    required this.th,
    required this.zh,
    required this.ja,
    this.aliases = const [],
  });

  final String code;
  final String en;
  final String ko;
  final String th;
  final String zh;
  final String ja;
  final List<String> aliases;

  String localizedName(String languageCode) {
    return switch (languageCode) {
      'ko' => ko,
      'th' => th,
      'zh' => zh,
      'ja' => ja,
      _ => en,
    };
  }

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return <String>[
      code,
      en,
      ko,
      th,
      zh,
      ja,
      ...aliases,
    ].any((value) => value.toLowerCase().contains(normalized));
  }
}

class CountryCatalog {
  CountryCatalog._();

  static const countries = <CountryOption>[
    CountryOption(
      code: 'TH',
      en: 'Thailand',
      ko: '태국',
      th: 'ประเทศไทย',
      zh: '泰国',
      ja: 'タイ',
      aliases: ['thai'],
    ),
    CountryOption(
      code: 'KR',
      en: 'South Korea',
      ko: '대한민국',
      th: 'เกาหลีใต้',
      zh: '韩国',
      ja: '韓国',
      aliases: ['korea', 'republic of korea', '한국', 'เกาหลี'],
    ),
    CountryOption(
      code: 'US',
      en: 'United States',
      ko: '미국',
      th: 'สหรัฐอเมริกา',
      zh: '美国',
      ja: 'アメリカ',
      aliases: ['usa', 'united states of america'],
    ),
    CountryOption(
      code: 'CN',
      en: 'China',
      ko: '중국',
      th: 'จีน',
      zh: '中国',
      ja: '中国',
    ),
    CountryOption(
      code: 'JP',
      en: 'Japan',
      ko: '일본',
      th: 'ญี่ปุ่น',
      zh: '日本',
      ja: '日本',
    ),
    CountryOption(
      code: 'TW',
      en: 'Taiwan',
      ko: '대만',
      th: 'ไต้หวัน',
      zh: '台湾',
      ja: '台湾',
    ),
    CountryOption(
      code: 'HK',
      en: 'Hong Kong',
      ko: '홍콩',
      th: 'ฮ่องกง',
      zh: '香港',
      ja: '香港',
    ),
    CountryOption(
      code: 'SG',
      en: 'Singapore',
      ko: '싱가포르',
      th: 'สิงคโปร์',
      zh: '新加坡',
      ja: 'シンガポール',
    ),
    CountryOption(
      code: 'MY',
      en: 'Malaysia',
      ko: '말레이시아',
      th: 'มาเลเซีย',
      zh: '马来西亚',
      ja: 'マレーシア',
    ),
    CountryOption(
      code: 'VN',
      en: 'Vietnam',
      ko: '베트남',
      th: 'เวียดนาม',
      zh: '越南',
      ja: 'ベトナム',
    ),
    CountryOption(
      code: 'PH',
      en: 'Philippines',
      ko: '필리핀',
      th: 'ฟิลิปปินส์',
      zh: '菲律宾',
      ja: 'フィリピン',
    ),
    CountryOption(
      code: 'ID',
      en: 'Indonesia',
      ko: '인도네시아',
      th: 'อินโดนีเซีย',
      zh: '印度尼西亚',
      ja: 'インドネシア',
    ),
    CountryOption(
      code: 'IN',
      en: 'India',
      ko: '인도',
      th: 'อินเดีย',
      zh: '印度',
      ja: 'インド',
    ),
    CountryOption(
      code: 'AU',
      en: 'Australia',
      ko: '호주',
      th: 'ออสเตรเลีย',
      zh: '澳大利亚',
      ja: 'オーストラリア',
    ),
    CountryOption(
      code: 'NZ',
      en: 'New Zealand',
      ko: '뉴질랜드',
      th: 'นิวซีแลนด์',
      zh: '新西兰',
      ja: 'ニュージーランド',
    ),
    CountryOption(
      code: 'GB',
      en: 'United Kingdom',
      ko: '영국',
      th: 'สหราชอาณาจักร',
      zh: '英国',
      ja: 'イギリス',
      aliases: ['uk', 'great britain'],
    ),
    CountryOption(
      code: 'CA',
      en: 'Canada',
      ko: '캐나다',
      th: 'แคนาดา',
      zh: '加拿大',
      ja: 'カナダ',
    ),
    CountryOption(
      code: 'DE',
      en: 'Germany',
      ko: '독일',
      th: 'เยอรมนี',
      zh: '德国',
      ja: 'ドイツ',
    ),
    CountryOption(
      code: 'FR',
      en: 'France',
      ko: '프랑스',
      th: 'ฝรั่งเศส',
      zh: '法国',
      ja: 'フランス',
    ),
    CountryOption(
      code: 'RU',
      en: 'Russia',
      ko: '러시아',
      th: 'รัสเซีย',
      zh: '俄罗斯',
      ja: 'ロシア',
    ),
    CountryOption(
      code: 'AE',
      en: 'United Arab Emirates',
      ko: '아랍에미리트',
      th: 'สหรัฐอาหรับเอมิเรตส์',
      zh: '阿拉伯联合酋长国',
      ja: 'アラブ首長国連邦',
      aliases: ['uae'],
    ),
  ];

  static Iterable<CountryOption> search(String query, {int limit = 8}) {
    if (query.trim().isEmpty) return const Iterable<CountryOption>.empty();
    return countries.where((country) => country.matches(query)).take(limit);
  }

  static CountryOption? byCode(String value) {
    final normalized = value.trim().toUpperCase();
    for (final country in countries) {
      if (country.code == normalized) return country;
    }
    return null;
  }

  static String displayName(String value, AppLocalizations l10n) {
    final country = byCode(value);
    return country?.localizedName(l10n.languageCode) ?? value.trim();
  }
}
