/// Friendship relationship model for the mutual friend graph.
class Friendship {
  final String requesterId;
  final String addresseeId;
  final FriendStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Friendship({
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  /// The user who initiated the request.
  String get initiatorId => requesterId;

  /// The other side of the relationship.
  String peerId(String selfId) =>
      requesterId == selfId ? addresseeId : requesterId;

  Map<String, dynamic> toJson() => {
        'requester_id': requesterId,
        'addressee_id': addresseeId,
        'status': status.name,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Friendship.fromJson(Map<String, dynamic> json) => Friendship(
        requesterId: json['requester_id']?.toString() ?? '',
        addresseeId: json['addressee_id']?.toString() ?? '',
        status: FriendStatus.values.firstWhere(
          (e) => e.name == (json['status']?.toString() ?? 'pending'),
          orElse: () => FriendStatus.pending,
        ),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

enum FriendStatus { pending, accepted, blocked }
