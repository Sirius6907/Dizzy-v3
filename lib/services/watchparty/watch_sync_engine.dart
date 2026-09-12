import 'dart:math';

/// WP-P2: co-watch sync engine. Host player is the source of truth;
/// guests follow by applying [WatchSyncMessage] snapshots.
///
/// Transport is Supabase Realtime Broadcast `control` (see
/// WatchPartyService); this file is pure protocol + math so it is unit
/// testable with no network. No media bytes or stream URLs travel —
/// only media IDs + playback positions.
class WatchSyncEngine {
  /// Heartbeat cadence for host state (spec: 2 Hz).
  static const heartbeatIntervalMs = 500;

  /// Drift above this triggers a silent resync on the guest.
  static const driftThresholdMs = 1500;

  /// Drift above this also shows a "catching up" toast.
  static const toastThresholdMs = 5000;

  /// Guest target position from a host snapshot, compensating clock offset
  /// and in-flight time. All inputs in milliseconds.
  static int targetPosition({
    required int hostPositionMs,
    required int hostSentAtMs,
    required int nowMs,
    required int clockOffsetMs,
  }) {
    final elapsed = max(0, nowMs - hostSentAtMs - clockOffsetMs);
    // Playback speed is applied by the caller tick; base target assumes 1x.
    return hostPositionMs + elapsed;
  }

  /// Returns the corrected guest position, or null when in tolerance
  /// (no seek needed).
  static int? resyncPosition({
    required int guestPositionMs,
    required int targetPositionMs,
  }) {
    final drift = targetPositionMs - guestPositionMs;
    if (drift.abs() <= driftThresholdMs) return null;
    return max(0, targetPositionMs);
  }

  /// True when the drift deserves a user-visible "catching up" hint.
  static bool shouldToast(int guestPositionMs, int targetPositionMs) =>
      (targetPositionMs - guestPositionMs).abs() > toastThresholdMs;

  /// Median clock offset from round-trip samples (join-time 3-ping).
  /// Positive = guest clock ahead of host.
  static int medianOffset(List<int> samples) {
    if (samples.isEmpty) return 0;
    final sorted = List<int>.of(samples)..sort();
    return sorted[sorted.length ~/ 2];
  }
}

/// Wire-format sync snapshot. `v` is the protocol version for forward compat.
class WatchSyncMessage {
  final int version;
  final String mediaRef;
  final String? mediaTitle;
  final int? season;
  final int? episode;
  final int positionMs;
  final bool playing;
  final double speed;
  final String? audioTrack;
  final String? subTrack;
  final int hostSentAtMs;

  const WatchSyncMessage({
    this.version = 2,
    required this.mediaRef,
    this.mediaTitle,
    this.season,
    this.episode,
    required this.positionMs,
    required this.playing,
    this.speed = 1.0,
    this.audioTrack,
    this.subTrack,
    required this.hostSentAtMs,
  });

  Map<String, dynamic> toJson() => {
        'v': version,
        'type': 'host_state',
        'media_ref': mediaRef,
        'media_title': mediaTitle,
        'season': season,
        'episode': episode,
        'position_ms': positionMs,
        'playing': playing,
        'speed': speed,
        'audio_track': audioTrack,
        'sub_track': subTrack,
        'host_sent_at': hostSentAtMs,
      };

  factory WatchSyncMessage.fromJson(Map<String, dynamic> json) =>
      WatchSyncMessage(
        version: int.tryParse(json['v']?.toString() ?? '') ?? 1,
        mediaRef: json['media_ref']?.toString() ?? '',
        mediaTitle: json['media_title']?.toString(),
        season: int.tryParse(json['season']?.toString() ?? ''),
        episode: int.tryParse(json['episode']?.toString() ?? ''),
        positionMs:
            int.tryParse(json['position_ms']?.toString() ?? '') ?? 0,
        playing: json['playing'] == true,
        speed: double.tryParse(json['speed']?.toString() ?? '') ?? 1.0,
        audioTrack: json['audio_track']?.toString(),
        subTrack: json['sub_track']?.toString(),
        hostSentAtMs:
            int.tryParse(json['host_sent_at']?.toString() ?? '') ?? 0,
      );

  bool get isUsable => version >= 1 && version <= 2 && mediaRef.isNotEmpty;
}

/// Guest-side control lock: while in a party, playback controls follow
/// the host. Guests keep volume + mic + chat.
class GuestControlPolicy {
  static const canSeek = false;
  static const canChangeSpeed = false;
  static const canChangeTracks = false;
  static const canAdjustVolume = true;
}
