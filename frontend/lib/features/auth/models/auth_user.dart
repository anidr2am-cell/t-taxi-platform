class AuthUser {
  const AuthUser({
    required this.id,
    required this.role,
    this.email,
    this.name,
    this.phone,
    this.locale,
    this.isActive = true,
  });

  final int id;
  final String role;
  final String? email;
  final String? name;
  final String? phone;
  final String? locale;
  final bool isActive;

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
    return AuthUser(
      id: json['id'] as int,
      role: json['role'] as String,
      email: json['email'] as String?,
      name: json['name'] as String?,
      phone: json['phone'] as String?,
      locale: json['locale'] as String?,
      isActive: json['isActive'] as bool? ?? true,
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
  };
}
