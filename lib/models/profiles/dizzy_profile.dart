class DizzyProfile {
  final String id;
  final String name;
  final String avatar;
  final bool isKids;
  final String? pinHash; // SHA-256; never raw PIN.
  final DateTime createdAt;
  // v1.3.3-T1.1: last-write-wins marker for cloud merge + admin history.
  final DateTime updatedAt;

  const DizzyProfile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.isKids,
    this.pinHash,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  bool get hasPin => pinHash != null && pinHash!.isNotEmpty;

  DizzyProfile copyWith({
    String? name,
    String? avatar,
    bool? isKids,
    String? pinHash,
    DateTime? updatedAt,
  }) => DizzyProfile(
    id: id,
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    isKids: isKids ?? this.isKids,
    pinHash: pinHash ?? this.pinHash,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'isKids': isKids,
    'pinHash': pinHash,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  Map<String, dynamic> toCloudJson() => {
    'profile_id': id,
    'name': name,
    'avatar': avatar,
    'is_kids': isKids,
    'pin_hash': pinHash,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory DizzyProfile.fromJson(Map<String, dynamic> json) {
    final created =
        DateTime.tryParse(
          (json['createdAt'] ?? json['created_at'])?.toString() ?? '',
        ) ??
        DateTime.now();
    return DizzyProfile(
      // Cloud rows carry profile_id, local rows carry id.
      id: (json['id'] ?? json['profile_id'])?.toString() ?? '',
      name: json['name']?.toString() ?? 'Profile',
      avatar: json['avatar']?.toString() ?? 'default',
      isKids: json['isKids'] == true || json['is_kids'] == true,
      pinHash: (json['pinHash'] ?? json['pin_hash'])?.toString(),
      createdAt: created,
      updatedAt:
          DateTime.tryParse(
            (json['updatedAt'] ?? json['updated_at'])?.toString() ?? '',
          ) ??
          created,
    );
  }
}
