class AuthUser {
  const AuthUser({
    required this.id,
    required this.role,
    this.email,
    this.name,
    this.phone,
    this.locale,
    this.isActive = true,
    this.authProvider,
    this.linkedProviders = const [],
  });

  final int id;
  final String role;
  final String? email;
  final String? name;
  final String? phone;
  final String? locale;
  final bool isActive;
  final String? authProvider;
  final List<String> linkedProviders;

  String get displayLabel {
    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      return trimmedName;
    }
    final trimmedEmail = email?.trim();
    if (trimmedEmail != null && trimmedEmail.isNotEmpty) {
      return trimmedEmail;
    }
    return 'Customer';
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawProviders = json['linkedProviders'];
    final linkedProviders = rawProviders is List
        ? rawProviders.map((item) => item.toString()).toList()
        : const <String>[];

    return AuthUser(
      id: json['id'] as int,
      role: json['role'] as String,
      email: json['email'] as String?,
      name: json['name'] as String?,
      phone: json['phone'] as String?,
      locale: json['locale'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      authProvider: json['authProvider'] as String?,
      linkedProviders: linkedProviders,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'email': email,
    'name': name,
    'phone': phone,
    'locale': locale,
    'isActive': isActive,
    if (authProvider != null) 'authProvider': authProvider,
    if (linkedProviders.isNotEmpty) 'linkedProviders': linkedProviders,
  };

  AuthUser copyWith({
    int? id,
    String? role,
    String? email,
    String? name,
    String? phone,
    String? locale,
    bool? isActive,
    String? authProvider,
    List<String>? linkedProviders,
  }) {
    return AuthUser(
      id: id ?? this.id,
      role: role ?? this.role,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      locale: locale ?? this.locale,
      isActive: isActive ?? this.isActive,
      authProvider: authProvider ?? this.authProvider,
      linkedProviders: linkedProviders ?? this.linkedProviders,
    );
  }
}
