import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/rust/api.dart';
import 'package:dizzy/rust/frb_generated.dart';

/// The Rust engine is a native library. It is built by:
///   cd rust/dizzy_adblock
///   cargo build --release --target x86_64-pc-windows-msvc
/// A machine without that build (CI) skips these cases instead of failing:
/// the app itself treats a missing engine as "allow everything".
void main() {
  final dll = File(
    'rust/dizzy_adblock/target/x86_64-pc-windows-msvc/release/dizzy_adblock.dll',
  );
  final available = Platform.isWindows && dll.existsSync();
  final skipReason = available ? null : 'native adblock lib not built here';

  setUpAll(() async {
    if (!available) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(dll.path));
  });

  const rules = [
    '||vinnyvower.cfd^',
    '||contain.remanpurflertawneys.cyou^',
    '||googletagmanager.com^',
    '@@||vidfast.vc^',
  ];

  test('blocks ad hosts and allows the page + media CDN', () async {
    final engine = await newEngine(rules: rules);

    expect(
      await engineMatch(
        engine: engine,
        url: 'https://vinnyvower.cfd/cuid/?f=https%3A%2F%2Fvidfast.vc',
        sourceHost: 'vidfast.vc',
        resourceType: 'xmlhttprequest',
      ),
      isTrue,
    );
    expect(
      await engineMatch(
        engine: engine,
        url: 'https://contain.remanpurflertawneys.cyou/gd/137978?md=abc',
        sourceHost: 'vidfast.vc',
        resourceType: 'xmlhttprequest',
      ),
      isTrue,
    );
    expect(
      await engineMatch(
        engine: engine,
        url: 'https://vidfast.vc/movie/550',
        sourceHost: 'vidfast.vc',
        resourceType: 'document',
      ),
      isFalse,
    );
    expect(
      await engineMatch(
        engine: engine,
        url: 'https://some-cdn.example.net/hls/550/index.m3u8',
        sourceHost: 'vidfast.vc',
        resourceType: 'xhr',
      ),
      isFalse,
    );
  }, skip: skipReason);

  test('a malformed URL is never blocked', () async {
    final engine = await newEngine(rules: rules);
    expect(
      await engineMatch(
        engine: engine,
        url: 'not a url',
        sourceHost: 'vidfast.vc',
        resourceType: 'xhr',
      ),
      isFalse,
    );
  }, skip: skipReason);
}
