import 'package:dizzy/services/share/native_share.dart';
import 'package:flutter_test/flutter_test.dart';

/// Zero-dep share contract: desktop/test host par channel call nahi hota,
/// caller ka clipboard fallback chalta hai. Android device par hi sheet.
void main() {
  test('non-Android host returns false (clipboard fallback path)', () async {
    expect(await NativeShare.shareText('Watch X with me on Dizzy!'), isFalse);
  });

  test('empty text never opens a sheet', () async {
    expect(await NativeShare.shareText(''), isFalse);
  });
}
