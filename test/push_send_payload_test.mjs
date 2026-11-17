import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

let buildFcmMessage;

test.before(async () => {
  const context = vm.createContext({ console, Date, AbortSignal, Request, Response });
  const code = stripTypeScriptTypes(
    await readFile(new URL('../supabase/functions/push-send/index.ts', import.meta.url), 'utf8'),
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
  buildFcmMessage = module.namespace.buildFcmMessage;
  assert.equal(typeof buildFcmMessage, 'function', 'buildFcmMessage must be exported');
});

const POSTER =
  'https://image.tmdb.org/t/p/w780/poster-release-2026.jpg';

const baseData = {
  kind: 'releases',
  title: 'Tonight: Dune',
  body: 'Your kind of story. One tap?',
};

test('poster url flows into the FCM android notification image field', () => {
  const message = buildFcmMessage('Tonight: Dune', 'Your kind of story. One tap?', {
    ...baseData,
    poster: POSTER,
  });
  assert.equal(message.android.notification.image, POSTER);
  assert.equal(message.notification.image, POSTER);
  assert.equal(message.notification.title, 'Tonight: Dune');
  assert.equal(message.data.poster, POSTER);
});

test('no poster means no image key is sent to FCM', () => {
  const message = buildFcmMessage('Tonight: Dune', 'Body', {
    ...baseData,
    poster: '',
  });
  assert.ok(!('image' in message.android.notification));
  assert.ok(!('image' in message.notification));
});
