class DizzyProfile {
  final String id;
  final String name;
  final String avatar;
  final bool isKids;
  final String? pinHash; // SHA-256; never raw PIN.
  final DateTime createdAt;

  const DizzyProfile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.isKids,
    this.pinHash,
    required this.createdAt,
  });

  bool get hasPin => pinHash != null && pinHash!.isNotEmpty;

  DizzyProfile copyWith({
    String? name,
    String? avatar,
    bool? isKids,
    String? pinHash,
  }) => DizzyProfile(
        id: id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        isKids: isKids ?? this.isKids,
        pinHash: pinHash ?? this.pinHash,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'isKids': isKids,
        'pinHash': pinHash,
        'createdAt': createdAt.toIso8601String(),
      };

  Map<String, dynamic> toCloudJson() => {
        'profile_id': id,
        'name': name,
        'avatar': avatar,
        'is_kids': isKids,
        'pin_hash': pinHash,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory DizzyProfile.fromJson(Map<String, dynamic> json) => DizzyProfile(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Profile',
        avatar: json['avatar']?.toString() ?? 'default',
        isKids: json['isKids'] == true || json['is_kids'] == true,
        pinHash: (json['pinHash'] ?? json['pin_hash'])?.toString(),
        createdAt: DateTime.tryParse(
                (json['createdAt'] ?? json['created_at'])?.toString() ?? '') ??
            DateTime.now(),
      );
}
