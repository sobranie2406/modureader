import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';

const root = new URL('../', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8');

test('Android builds resolve the patched audio backend', () => {
    assert.match(read('pubspec.yaml'), /dependency_overrides:\s+\n?\s*audioplayers_android:\s+path: third_party\/audioplayers_android/);
});

test('starting Android speech reports native playback and acquires its wake lock', () => {
    const source = read('third_party/audioplayers_android/android/src/main/kotlin/xyz/luan/audioplayers/player/MediaPlayerWrapper.kt');
    const start = source.match(/override fun start\(\) \{([\s\S]*?)\n    \}/)?.[1];
    assert.ok(start);
    assert.match(start, /setRate\(wrappedPlayer.rate\)/);
    assert.match(start, /\n\s*mediaPlayer.start\(\)/);
    assert.ok(start.indexOf('setRate(') < start.lastIndexOf('mediaPlayer.start()'));
});

test('lazy native creation honors the context set before the first audio source', () => {
    const source = read('third_party/audioplayers_android/android/src/main/kotlin/xyz/luan/audioplayers/player/MediaPlayerWrapper.kt');
    const create = source.match(/private fun createMediaPlayer[\s\S]*?return mediaPlayer/)?.[0];
    assert.match(create, /if \(wrappedPlayer.context.stayAwake\)/);
    assert.match(create, /mediaPlayer.setWakeMode\(wrappedPlayer.applicationContext, PowerManager.PARTIAL_WAKE_LOCK\)/);
});
