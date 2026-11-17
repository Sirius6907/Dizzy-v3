import 'package:dizzy/models/audiobook/audiobook_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression for a defect seen on-device (2026-11-14): the audiobook
/// catalogue ships HTML entities in its titles, and they reached the UI
/// literally - "The Baker Who&#8217;s 40% Stronger Than You" instead of
/// "The Baker Who's 40% Stronger Than You". The music side has decoded
/// them all along; the audiobook side did not.
void main() {
  test('audiobook titles and authors are decoded', () {
    final book = Audiobook.fromJson({
      'uuid': 'u1',
      'audioBookId': 'a1',
      'dynamicSlugId': 'd1',
      'title': 'The Baker Who&#8217;s 40% Stronger Than You',
      'author': 'Alyson Belle &#8211; Fantasy',
      'coverImage': ' c ',
      'source': 's',
      'pageUrl': 'p',
    });

    expect(book.title, contains('Who'));
    expect(book.title, isNot(contains('&#')));
    expect(book.title, contains('’'));
    expect(book.author ?? '', isNot(contains('&#')));
  });

  test('a clean title is left alone', () {
    final book = Audiobook.fromJson({
      'uuid': 'u2',
      'audioBookId': 'a2',
      'dynamicSlugId': 'd2',
      'title': 'Dahaan',
      'coverImage': '',
      'source': 's',
      'pageUrl': 'p',
    });
    expect(book.title, 'Dahaan');
    expect(book.author, isNull);
  });

  test('direct construction decodes too (the scraper path)', () {
    // The scraper builds Audiobook objects itself, not through fromJson -
    // that is why the first fix (in fromJson only) did not change the UI.
    final book = Audiobook(
      uuid: 'u3',
      audioBookId: 'a3',
      dynamicSlugId: 'd3',
      title: 'Alyson Belle &#8211; Fantasy',
      author: 'Alyson &#8217; Belle',
      coverImage: '',
      source: 's',
      pageUrl: 'p',
    );
    expect(book.title, isNot(contains('&#')));
    expect(book.title, contains('–'));
    expect(book.author ?? '', isNot(contains('&#')));
  });
}
