import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

let copyFor;

test.before(async () => {
  const context = vm.createContext({ console, Date, AbortSignal, Request, Response });
  const code = stripTypeScriptTypes(
    await readFile(new URL('../supabase/functions/push-brain/index.ts', import.meta.url), 'utf8'),
  );
  const module = new vm.SourceTextModule(code, { context });
  await module.link(async (specifier) => {
    if (specifier.includes('/http/server.ts')) {
      return new vm.SyntheticModule(['serve'], function () {
        this.setExport('serve', () => {});
      }, { context });
    }
    if (specifier.includes('@supabase/supabase-js')) {
      return new vm.SyntheticModule(['createClient'], function () {
        this.setExport('createClient', () => ({}));
      }, { context });
    }
    throw new Error(`Unexpected dependency: ${specifier}`);
  });
  await module.evaluate();
  copyFor = module.namespace.copyFor;
});

const hindiMovie = {
  id: 1, media_type: 'movie', tmdb_id: 1, title: 'Kalki 2898 AD',
  lang: 'hi', year: 2024, rating: '7.1', poster: null, genres: ['Science Fiction'],
};
const englishMovie = {
  id: 2, media_type: 'movie', tmdb_id: 2, title: 'Dune: Part Two',
  lang: 'en', year: 2024, rating: '8.1', poster: null, genres: ['Adventure'],
};
const hindiShow = {
  id: 3, media_type: 'tv', tmdb_id: 3, title: 'Mirzapur',
  lang: 'hi', year: 2024, rating: '8.4', poster: null, genres: ['Crime'],
};

const EMOJI = /\p{Extended_Pictographic}/gu;
const HINGLISH_TOKEN = /\b(tum|aaj|raat|taste|dekh)\b/i;

test('playful Hindi copy is Hinglish, names the title and puts 1-2 emoji in the title', () => {
  const copy = copyFor(hindiMovie, 'playful');
  assert.match(copy.title, /Kalki 2898 AD/);
  const emojiCount = [...`${copy.title}`.matchAll(EMOJI)].length;
  assert.ok(emojiCount >= 1 && emojiCount <= 2, `title emoji count ${emojiCount}`);
  // Emoji are a title garnish, never body decoration.
  assert.equal([...`${copy.body}`.matchAll(EMOJI)].length, 0);
  assert.match(`${copy.title} ${copy.body}`, HINGLISH_TOKEN);
  assert.ok(copy.body.length <= 100);
  assert.ok(!copy.title.toLowerCase().includes('new on dizzy'));
});

test('playful English copy stays in English with an emoji title', () => {
  const copy = copyFor(englishMovie, 'playful');
  assert.match(copy.title, /Dune: Part Two/);
  const emojiCount = [...`${copy.title}`.matchAll(EMOJI)].length;
  assert.ok(emojiCount >= 1 && emojiCount <= 2, `title emoji count ${emojiCount}`);
  assert.ok(!HINGLISH_TOKEN.test(`${copy.title} ${copy.body}`));
  assert.match(copy.body, /(tonight|one tap|kind of|movie night)/i);
  assert.ok(copy.body.length <= 100);
});

test('playful series copy keeps emoji in the title and talks episodes', () => {
  const copy = copyFor(hindiShow, 'playful');
  const emojiCount = [...`${copy.title}`.matchAll(EMOJI)].length;
  assert.ok(emojiCount >= 1 && emojiCount <= 2, `title emoji count ${emojiCount}`);
  assert.match(`${copy.title} ${copy.body}`, /episode|episodes/i);
  assert.match(`${copy.title} ${copy.body}`, HINGLISH_TOKEN);
});

test('titles are short enough for a notification shade (<=40) and bodies <=100 for every tone', () => {
  for (const tone of ['warm', 'playful']) {
    for (const candidate of [hindiMovie, englishMovie, hindiShow]) {
      const copy = copyFor(candidate, tone);
      assert.ok(copy.title.length > 0 && copy.body.length > 0, `empty copy for ${tone}`);
      assert.ok(copy.title.length <= 40, `title too long (${copy.title.length}): ${copy.title}`);
      assert.ok(copy.body.length <= 100, `body too long (${copy.body.length}): ${copy.body}`);
      const text = `${copy.title} ${copy.body}`;
      assert.ok(!/watchlist|we knew|you asked for|guaranteed|last chance/i.test(text));
      assert.ok(!text.includes('undefined') && !text.includes('null'));
    }
  }
});

test('warm copy stays plain: no emoji anywhere', () => {
  for (const candidate of [hindiMovie, englishMovie, hindiShow]) {
    const copy = copyFor(candidate, 'warm');
    assert.equal([...`${copy.title}${copy.body}`.matchAll(EMOJI)].length, 0);
  }
});

test('the same title does not produce a different message every run', () => {
  assert.deepEqual(copyFor(hindiMovie, 'playful'), copyFor(hindiMovie, 'playful'));
});

test('different titles get some variety instead of one template', () => {
  const bodies = new Set([
    copyFor(hindiMovie, 'playful').body,
    copyFor({ ...hindiMovie, title: 'Jawan' }, 'playful').body,
    copyFor({ ...hindiMovie, title: 'Animal' }, 'playful').body,
    copyFor({ ...hindiMovie, title: 'Pathaan' }, 'playful').body,
  ]);
  assert.ok(bodies.size >= 2, `only ${bodies.size} distinct bodies`);
});

test('unknown tone falls back to warm instead of breaking delivery', () => {
  const copy = copyFor(englishMovie, 'something-else');
  assert.ok(copy.title.length > 0 && copy.body.length > 0);
  assert.match(copy.body, /new|ready|tap/i);
  assert.equal([...`${copy.title}`.matchAll(EMOJI)].length, 0);
});
