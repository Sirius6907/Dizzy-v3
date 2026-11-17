import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:torrserver_flutter/torrserver_flutter.dart';

import '../../models/download/download_task_model.dart';
import '../../utils/torrent/torrent_trackers.dart';
import '../download/download_service.dart';
import '../debrid/utils/debrid_media_matcher.dart';
import '../errors/app_log.dart';
import 'torrent_file_guard.dart';
import 'torrent_warmup_policy.dart';

/// Rich torrent statistics object.
class TorrentStats {
  /// Download speed in **megabytes per second** (MB/s). Multiply by 8 for
  /// Mbps — the name on purpose unlike [StartupBandwidthPolicy] which works
  /// in Mbps.
  final double speedMBps;
  final int activePeers;
  final int totalPeers;
  final double cachePercent;
  final int loadedBytes;
  final int totalBytes;
  final String hash;
  final bool isConnected;

  const TorrentStats({
    required this.speedMBps,
    required this.activePeers,
    required this.totalPeers,
    required this.cachePercent,
    required this.loadedBytes,
    required this.totalBytes,
    required this.hash,
    required this.isConnected,
  });

  double get speedKbps => speedMBps * 1024;
  String get speedLabel => speedMBps >= 1.0
      ? '${speedMBps.toStringAsFixed(2)} MB/s'
      : '${speedKbps.toStringAsFixed(0)} KB/s';
  String get peersLabel => '$activePeers / $totalPeers';
  String get cacheLabel => '${cachePercent.toStringAsFixed(1)}%';
}

/// Engine lifecycle states.
enum EngineState { stopped, starting, ready, error }

/// Production-grade TorrentStreamService powered by torrserver_flutter.
///
/// Provides high performance HTTP streaming with automatic free-port allocation,
/// cross-platform subprocess / FFI management, intelligent file selection
/// (via ParseTorrentTitle), and real-time swarm statistics.
class TorrentStreamService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final TorrentStreamService _instance =
      TorrentStreamService._internal();
  factory TorrentStreamService() => _instance;
  TorrentStreamService._internal() : _controller = createTorrServerController();

  @visibleForTesting
  TorrentStreamService.withController(this._controller);

  // ── Controller & State ─────────────────────────────────────────────────────
  final TorrServerController _controller;
  TorrServerController get controller => _controller;

  EngineState _state = EngineState.stopped;
  EngineState get state => _state;

  void Function(EngineState state)? onStateChanged;
  void Function(String line)? onLogLine;

  /// Active torrent hashes tracked by the service.
  final Set<String> _activeTorrents = {};

  /// Latest torrent update snapshots keyed by infohash.
  final Map<String, TorrentInfo> _latestUpdates = {};

  /// Swarm throughput (Mbps) seen during the last warm-up. Exposed so the
  /// player can cap the NEXT source when a torrent is rejected as too slow.
  double? lastWarmupMbps;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Starts the TorrServer engine using native defaults. Safe to call multiple times.
  Future<bool> start() async {
    if (_controller.isRunning && _state == EngineState.ready) return true;
    if (_state == EngineState.starting) {
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_controller.isRunning && _state == EngineState.ready) return true;
        if (_state == EngineState.error) return false;
      }
      return false;
    }

    _setState(EngineState.starting);
    try {
      // TorrServer's web server binds every interface by default and has no
      // auth, so on shared Wi-Fi any LAN device could add/list/stream
      // torrents. The app only ever talks to 127.0.0.1.
      _log('Starting TorrServer engine on loopback...');
      await _controller.start(extraArgs: const ['-i', '127.0.0.1']);
      final version = await _controller.echo();
      _setState(EngineState.ready);
      _log(
        'TorrServer ready at ${_controller.baseUrl} (version: $version, loopback-only)',
      );
      return true;
    } catch (e, st) {
      _log('Failed to start TorrServer: $e\n$st');
      _setState(EngineState.error);
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stream a torrent — main entry point
  // ─────────────────────────────────────────────────────────────────────────

  /// Adds a magnet, waits for metadata, selects the right file, starts an
  /// HTTP stream, and returns the stream URL.
  Future<String?> streamTorrent(
    String magnetLink, {
    int? season,
    int? episode,
    String? episodeTitle,
    int? fileIdx,
    int requiredBps = 0,
  }) async {
    if (!_controller.isRunning || _state != EngineState.ready) {
      final started = await start();
      if (!started) {
        _log('Cannot stream: TorrServer engine failed to start.');
        return null;
      }
    }

    final rawHash = _extractHash(magnetLink);
    var formattedMagnet =
        (rawHash != null && !magnetLink.startsWith('magnet:?'))
        ? 'magnet:?xt=urn:btih:$rawHash'
        : magnetLink;

    // Every magnet gets public trackers merged in. A DHT-only magnet makes
    // the engine hunt for the first peer for tens of seconds (and often
    // finds nobody), which the player used to report as "no working peers".
    formattedMagnet = magnetWithTrackers(formattedMagnet);

    final displayName = _extractDisplayName(formattedMagnet);

    try {
      _log('Adding torrent to TorrServer...');
      final added = await _controller.addTorrent(
        magnet: formattedMagnet,
        title: displayName.isNotEmpty ? displayName : null,
        saveToDb: false,
      );

      final hash = added.hash.isNotEmpty
          ? added.hash.toLowerCase()
          : (rawHash ?? '').toLowerCase();

      if (hash.isNotEmpty) {
        _activeTorrents.add(hash);
        _latestUpdates[hash] = added;
      }

      _log('Torrent added: $hash ($displayName). Waiting for metadata...');

      // Wait for torrent metadata / file list
      final files = await _waitForMetadata(hash);
      if (files == null || files.isEmpty) {
        _log('No files found in torrent metadata');
        return null;
      }

      // Decoy releases carry a 1-2 GB `.exe` as the only file. Selecting it
      // hands Windows malware to the player and black-screens the user.
      final videoFiles = files
          .where((f) => TorrentFileGuard.isVideo(f.path))
          .toList();
      if (videoFiles.isEmpty) {
        _log('Torrent has no playable video file (decoy payload only)');
        return null;
      }

      // Auto file picker
      final selectedFileId = _selectFile(
        videoFiles,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle,
        preferredIdx: fileIdx,
      );

      if (selectedFileId == null) {
        _log('No suitable media file found in torrent');
        return null;
      }

      final selectedFile = videoFiles.firstWhere(
        (f) => f.id == selectedFileId,
        orElse: () => videoFiles.first,
      );
      _log(
        'Selected file #${selectedFile.id}: "${selectedFile.path}" (${_formatBytes(selectedFile.length)})',
      );

      final streamUri = _controller.streamUrl(hash, fileIndex: selectedFile.id);
      _log('HTTP Stream URL generated: $streamUri');

      final healthy = await _warmUpStream(
        streamUri,
        hash,
        requiredBps: requiredBps,
      );
      if (!healthy) {
        // Never hand a starved swarm to mpv: it reports "opened" and then
        // sits on a black frame forever (94s in the 2026-11-09 audit).
        _log('Torrent rejected before opening the player (starved swarm).');
        await removeTorrent(hash);
        return null;
      }

      return streamUri.toString();
    } catch (e, st) {
      _log('streamTorrent error: $e\n$st');
      return null;
    }
  }

  /// Kick-starts the exact file mpv will request and waits until the swarm
  /// has proven it can feed it. Returns false when the torrent is hopeless —
  /// the caller must then move on to another source instead of opening mpv.
  ///
  /// The decision is based on TorrServer counters plus the bytes actually
  /// handed to a live reader ([TorrentWarmupPolicy]): buffered bytes, ACTIVE
  /// peers (DHT `total_peers` lies), download speed and byte growth. The old
  /// version returned "ready" at 0 bytes after a 2s preload grace, which is
  /// what produced the endless spinner — and a later version cancelled its
  /// reader after 3s, which made healthy torrents look starved.
  Future<bool> _warmUpStream(
    Uri url,
    String hash, {
    int requiredBps = 0,
  }) async {
    final clock = Stopwatch()..start();

    // Keep ONE reader alive for the whole warm-up window. TorrServer downloads
    // on demand: the old version requested only 1 MB, cancelled the request
    // after 3 s and then watched a frozen `loaded_size` — so a healthy swarm
    // that needed a few seconds to open the piece looked "starved" and got
    // rejected with "no working peers" (2026-11-15).
    http.Client? reader;
    StreamSubscription<List<int>>? subscription;
    var servedBytes = 0;
    var readerStopped = false;

    Future<void> pump() async {
      while (!readerStopped) {
        final client = http.Client();
        try {
          final request = http.Request('GET', url)
            ..headers['Range'] = 'bytes=0-67108863';
          final response = await client
              .send(request)
              .timeout(const Duration(seconds: 8));
          if (readerStopped || response.statusCode >= 400) {
            client.close();
            if (readerStopped) return;
            await Future<void>.delayed(const Duration(milliseconds: 400));
            continue;
          }
          final sub = response.stream.listen(
            (chunk) => servedBytes += chunk.length,
            onError: (_) {},
            cancelOnError: false,
          );
          reader = client;
          subscription = sub;
          // Lost the race with the warm-up loop's finally block: the client
          // was already closed, so close this one too instead of leaking it.
          if (readerStopped) {
            await sub.cancel();
            client.close();
          }
          return;
        } catch (_) {
          client.close();
          if (readerStopped) return;
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }

    unawaited(pump());

    try {
      var lastBuffered = -1;
      var lastGrowthAt = Duration.zero;
      var lastLogAt = -1;
      while (clock.elapsed < TorrentWarmupPolicy.maxWait) {
        try {
          final info = await _controller.getTorrent(hash);
          _latestUpdates[hash] = info;

          // Bytes actually handed to our reader prove the swarm is feeding
          // the stream, whatever `loaded_size` says.
          final buffered = info.loadedSize > servedBytes
              ? info.loadedSize
              : servedBytes;
          if (buffered > lastBuffered) {
            lastBuffered = buffered;
            lastGrowthAt = clock.elapsed;
          }
          final sinceGrowth = clock.elapsed - lastGrowthAt;
          if (info.downloadSpeed > 0) {
            // TorrServer reports bytes/s; the player's start gate expects
            // Mbps. Skipping the ×8 made a healthy 12 Mbps swarm look like
            // 1.5 Mbps and capped the replacement source to 480p.
            lastWarmupMbps = info.downloadSpeed * 8 / 1024 / 1024;
          }

          final verdict = TorrentWarmupPolicy.evaluate(
            loadedBytes: info.loadedSize,
            servedBytes: servedBytes,
            activePeers: info.activePeers,
            speedBps: info.downloadSpeed.round(),
            sinceBytesGrew: sinceGrowth,
            elapsed: clock.elapsed,
          );

          // One line per second — enough for logcat triage, not spam.
          final sec = clock.elapsed.inSeconds;
          if (sec != lastLogAt) {
            lastLogAt = sec;
            _log(
              'Warm-up ${sec}s: ${(buffered / 1048576).toStringAsFixed(2)}MB '
              'buffered of ${(info.torrentSize / 1048576).toStringAsFixed(0)}MB, '
              'peers ${info.activePeers}/${info.totalPeers}, '
              'speed ${(info.downloadSpeed / 1048576).toStringAsFixed(2)}MB/s, '
              'growth ${sinceGrowth.inSeconds}s ago',
            );
          }

          if (verdict == TorrentReadiness.ready) {
            // A swarm that is moving but far below the file's bitrate will
            // stall a few seconds into playback: reject it now and let the
            // caller fall back to a smaller/HTTP source. Only when the buffer
            // has actually stopped growing — a burst-fed swarm reports ~0
            // speed for one poll between pieces.
            final minimum = TorrentWarmupPolicy.minimumSustainableBps(
              requiredBps,
            );
            if (requiredBps > 0 &&
                info.downloadSpeed < minimum &&
                sinceGrowth >= const Duration(seconds: 3) &&
                buffered < 8 * 1024 * 1024) {
              _log(
                'Swarm too slow for this file: '
                '${(info.downloadSpeed / 1048576).toStringAsFixed(2)}MB/s < '
                '${(minimum / 1048576).toStringAsFixed(2)}MB/s needed '
                '(${(requiredBps / 1000000).toStringAsFixed(1)}Mbps file).',
              );
              return false;
            }
            _log(
              'Torrent warm-up ready: ${buffered ~/ 1048576} MB buffered, '
              'peers ${info.activePeers} '
              '(${(info.downloadSpeed / 1048576).toStringAsFixed(2)} MB/s)',
            );
            return true;
          }
          if (verdict == TorrentReadiness.hopeless) {
            _log(
              'Torrent hopeless after ${clock.elapsed.inSeconds}s: '
              '${(buffered / 1048576).toStringAsFixed(2)}MB buffered, '
              'peers ${info.activePeers}/${info.totalPeers} — rejecting.',
            );
            return false;
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      _log('Torrent warm-up gave up after ${clock.elapsed.inSeconds}s');
      return false;
    } finally {
      readerStopped = true;
      await subscription?.cancel();
      reader?.close();
    }
  }

  /// Adds a magnet, waits for metadata, and returns full TorrentInfo including all files.
  Future<TorrentInfo?> getTorrentMetadata(String magnetLink) async {
    try {
      final started = await start();
      if (!started) return null;

      final rawHash = _extractHash(magnetLink);
      if (rawHash == null) {
        _log('Invalid magnet link / hash: $magnetLink');
        return null;
      }
      final hash = rawHash.toLowerCase();

      final formattedMagnet = !magnetLink.startsWith('magnet:?')
          ? 'magnet:?xt=urn:btih:$rawHash'
          : magnetLink;

      final title = _extractDisplayName(formattedMagnet);
      _log('Adding torrent for file list inspection: $hash ($title)');
      await _controller.addTorrent(
        magnet: formattedMagnet,
        title: title.isNotEmpty ? title : null,
        saveToDb: false,
      );
      _activeTorrents.add(hash);

      final files = await _waitForMetadata(hash);
      if (files == null || files.isEmpty) return null;

      return await _controller.getTorrent(hash);
    } catch (e, st) {
      _log('getTorrentMetadata error: $e\n$st');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Metadata polling
  // ─────────────────────────────────────────────────────────────────────────

  /// Waits for the magnet's file list — with an EARLY abort when the swarm is
  /// not answering. A magnet for a dead torrent used to burn the full 45s
  /// (2026-11-09 audit: player sat on "Gathering metadata & peers…" for 45s,
  /// then dropped to the picker). DHT-only magnets routinely need 10-30s to
  /// find the first peer, so the abort waits 16s AND requires peers,
  /// seeders and throughput to all be zero — TorrServer reports
  /// `active_peers = 0` between transfers even on a healthy swarm.
  Future<List<TorrentFileStat>?> _waitForMetadata(
    String hash, {
    Duration timeout = const Duration(seconds: 30),
    Duration noPeerAbort = const Duration(seconds: 16),
    Duration pollInterval = const Duration(milliseconds: 300),
  }) async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      try {
        final info = await _controller.getTorrent(hash);
        _latestUpdates[hash] = info;
        if (info.fileStats.isNotEmpty) {
          _log(
            'Metadata ready in ${stopwatch.elapsed.inMilliseconds}ms '
            '(${info.fileStats.length} files, ${info.activePeers} active peers)',
          );
          return info.fileStats;
        }
        if (stopwatch.elapsed >= noPeerAbort &&
            info.activePeers <= 0 &&
            info.connectedSeeders <= 0 &&
            info.downloadSpeed <= 0) {
          _log(
            'No peers after ${stopwatch.elapsed.inSeconds}s — aborting magnet '
            '(hash $hash). Swarm cannot deliver metadata.',
          );
          return null;
        }
      } catch (e) {
        // The engine no longer knows this torrent (it was dropped, or the
        // session was cleaned up). Polling a 404 cannot succeed, so the wait
        // ends here instead of burning the whole timeout budget on a dead
        // hash - and instead of flooding the log every 300ms.
        if (isTorrentGone(e)) {
          _log(
            'Torrent $hash is no longer in the engine - aborting the metadata '
            'wait',
          );
          return null;
        }
        _log('Polling metadata error: $e');
      }
      await Future.delayed(pollInterval);
    }

    _log('Metadata timeout after ${timeout.inSeconds}s for hash $hash');
    return null;
  }

  /// True when the error means "the engine does not have this torrent".
  ///
  /// TorrServer answers 404 for a hash it never got or already dropped. Once
  /// that happens the torrent can never appear under the same hash, so the
  /// wait has to end.
  static bool isTorrentGone(Object error) =>
      error is TorrServerHttpException && error.statusCode == 404;

  // ─────────────────────────────────────────────────────────────────────────
  // File selection — intelligent auto file picker
  // ─────────────────────────────────────────────────────────────────────────
  // File selection — intelligent auto file picker
  // ─────────────────────────────────────────────────────────────────────────

  int? _selectFile(
    List<TorrentFileStat> files, {
    int? season,
    int? episode,
    String? episodeTitle,
    int? preferredIdx,
  }) {
    if (files.isEmpty) return null;

    final picked = DebridMediaMatcher.pickMediaFile<TorrentFileStat>(
      files,
      fileIndex: preferredIdx,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      name: (f) => f.path,
      size: (f) => f.length,
    );

    return picked?.id;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Torrent management & Statistics
  // ─────────────────────────────────────────────────────────────────────────

  /// Removes a torrent from TorrServer.
  Future<void> removeTorrent(String magnetOrHash) async {
    final hash = _extractHash(magnetOrHash) ?? magnetOrHash.toLowerCase();
    _activeTorrents.remove(hash);
    _latestUpdates.remove(hash);
    if (_controller.isRunning) {
      try {
        await _controller.removeTorrent(hash);
        _log('Removed torrent $hash from TorrServer');
      } catch (e) {
        _log('Error removing torrent $hash: $e');
      }
    }
  }

  /// Cheap synchronous liveness hint: true when this torrent is already
  /// tracked by the running engine and has bytes ready to serve, so the
  /// first player request won't wait on metadata/DHT.
  bool isCached(String magnetOrHash) {
    final hash = _extractHash(magnetOrHash) ?? magnetOrHash.toLowerCase();
    final info = _latestUpdates[hash];
    if (info == null) return false;
    // Preloaded bytes are a request marker, not data — only real buffered
    // bytes mean "safe to open without waiting".
    return info.loadedSize > 0;
  }

  /// One-shot live refresh for the playback watchdog (no subscription).
  /// Returns null when the engine/torrent is gone.
  Future<TorrentStats?> refreshStats(String magnetOrHash) async {
    final hash = _extractHash(magnetOrHash) ?? magnetOrHash.toLowerCase();
    if (!_controller.isRunning) return null;
    try {
      final info = await _controller.getTorrent(hash);
      _latestUpdates[hash] = info;
    } catch (_) {
      return null;
    }
    return getTorrentStats(hash);
  }

  /// Returns latest cached or live stats for a torrent.
  TorrentStats? getTorrentStats(String magnetOrHash) {
    final hash = _extractHash(magnetOrHash) ?? magnetOrHash.toLowerCase();
    final info = _latestUpdates[hash];
    if (info == null) return null;

    final speedMBps = info.downloadSpeed / 1024 / 1024;
    final total = info.torrentSize;
    final loaded = info.loadedSize;
    final percent = total > 0 ? (loaded / total) * 100 : 0.0;

    return TorrentStats(
      speedMBps: speedMBps,
      activePeers: info.activePeers,
      totalPeers: info.totalPeers,
      cachePercent: percent,
      loadedBytes: loaded,
      totalBytes: total,
      hash: hash,
      isConnected: info.activePeers > 0 || info.downloadSpeed > 0,
    );
  }

  /// Streams stats at [interval] for a torrent.
  Stream<TorrentStats> statsStream(
    String magnetOrHash, {
    Duration interval = const Duration(seconds: 1),
  }) {
    final hash = _extractHash(magnetOrHash) ?? magnetOrHash.toLowerCase();
    final streamController = StreamController<TorrentStats>();
    Timer? timer;

    streamController.onListen = () {
      timer = Timer.periodic(interval, (_) async {
        if (!_controller.isRunning || streamController.isClosed) return;
        try {
          final info = await _controller.getTorrent(hash);
          _latestUpdates[hash] = info;
          final stats = getTorrentStats(hash);
          if (stats != null && !streamController.isClosed) {
            streamController.add(stats);
          }
        } catch (_) {}
      });
    };

    streamController.onCancel = () {
      timer?.cancel();
      streamController.close();
    };

    return streamController.stream;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stop / cleanup
  // ─────────────────────────────────────────────────────────────────────────

  /// Drops active torrents from RAM to free resources when closing player.
  Future<void> cleanup() async {
    final downloadingHashes = <String>{};
    for (final task in DownloadService.instance.tasksNotifier.value) {
      if (task.isDownloading || task.status == DownloadStatus.queued) {
        final h1 = task.infoHash != null ? _extractHash(task.infoHash!) : null;
        final h2 = task.magnet != null ? _extractHash(task.magnet!) : null;
        final h3 = task.rawUrl != null ? _extractHash(task.rawUrl!) : null;
        if (h1 != null) downloadingHashes.add(h1);
        if (h2 != null) downloadingHashes.add(h2);
        if (h3 != null) downloadingHashes.add(h3);
      }
    }

    for (final hash in List<String>.from(_activeTorrents)) {
      if (downloadingHashes.contains(hash.toLowerCase())) {
        continue;
      }
      try {
        if (_controller.isRunning) {
          await _controller.dropTorrent(hash);
        }
      } catch (_) {}
    }
    _activeTorrents.removeWhere(
      (h) => !downloadingHashes.contains(h.toLowerCase()),
    );
    _log('TorrentStreamService cleanup completed.');
  }

  /// Completely stops the TorrServer engine process.
  Future<void> stop() async {
    if (_controller.isRunning) {
      try {
        await _controller.stop();
        _log('TorrServer stopped.');
      } catch (e) {
        _log('Error stopping TorrServer: $e');
      }
    }
    _activeTorrents.clear();
    _latestUpdates.clear();
    _setState(EngineState.stopped);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  static final _hashRegExp = RegExp(r'[0-9a-fA-F]{40}');

  String? _extractHash(String magnetOrHash) {
    final match = _hashRegExp.firstMatch(magnetOrHash);
    return match?.group(0)?.toLowerCase();
  }

  String _extractDisplayName(String magnet) {
    try {
      final match = RegExp(r'[?&]dn=([^&]+)').firstMatch(magnet);
      if (match != null && match.group(1) != null) {
        return Uri.decodeComponent(match.group(1)!.replaceAll('+', ' '));
      }
    } catch (_) {}
    return '';
  }

  String _formatBytes(num bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(i == 0 ? 0 : 2)} ${suffixes[i]}';
  }

  void _setState(EngineState s) {
    if (_state == s) return;
    _state = s;
    onStateChanged?.call(s);
  }

  void _log(String message) {
    AppLog.d('[TorrentStream] $message');
    onLogLine?.call(message);
  }
}
