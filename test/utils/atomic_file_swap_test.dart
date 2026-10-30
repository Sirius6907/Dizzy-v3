import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/utils/download/atomic_file_swap.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('atomic_swap_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('promotes source when no target exists', () async {
    final source = File('${dir.path}/a.part');
    await source.writeAsString('fresh');
    final target = '${dir.path}/a.mp4';

    await promoteFile(source, target);

    expect(await File(target).readAsString(), 'fresh');
    expect(await source.exists(), isFalse);
    expect(await File('$target.bak').exists(), isFalse);
  });

  test('replaces an existing target and drops the backup', () async {
    final source = File('${dir.path}/b.part');
    await source.writeAsString('new');
    final target = File('${dir.path}/b.mp4');
    await target.writeAsString('old');

    await promoteFile(source, target.path);

    expect(await target.readAsString(), 'new');
    expect(await File('${target.path}.bak').exists(), isFalse);
  });

  test('restores the previous target when the swap fails', () async {
    final target = File('${dir.path}/c.mp4');
    await target.writeAsString('keep me');
    final missing = File('${dir.path}/c.part');

    await expectLater(
      promoteFile(missing, target.path),
      throwsA(isA<FileSystemException>()),
    );

    expect(await target.readAsString(), 'keep me');
    expect(await File('${target.path}.bak').exists(), isFalse);
  });
}
