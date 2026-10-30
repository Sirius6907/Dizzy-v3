import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:torrserver_flutter/torrserver_flutter.dart';

import 'package:dizzy/services/stream/torrent_stream_service.dart';

class _FakeController implements TorrServerController {
  List<String>? lastExtraArgs;

  @override
  Future<void> start({
    int? port,
    TorrServerSettings? settings,
    Directory? dataDir,
    List<String>? extraArgs,
    String? customBinaryPath,
  }) async {
    lastExtraArgs = extraArgs;
  }

  @override
  bool get isRunning => false;

  @override
  Uri? get baseUrl => Uri.parse('http://127.0.0.1:8090');

  @override
  int? get port => 8090;

  @override
  Future<String> echo() async => 'MatriX.147.2';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('binds TorrServer HTTP server to loopback only', () async {
    final controller = _FakeController();
    final service = TorrentStreamService.withController(controller);

    final started = await service.start();

    expect(started, isTrue);
    expect(controller.lastExtraArgs, ['-i', '127.0.0.1']);
  });
}
