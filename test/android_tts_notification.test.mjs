import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('every Android build applies the silent notification patch', () => {
    assert.match(read('android/build.gradle'), /apply from: 'modu_audio_notification.gradle'/);
    const patch = read('android/modu_audio_notification.gradle');
    for (const setting of ['.setSilent(true)', '.setOnlyAlertOnce(true)',
        '.setDefaults(0)', '.setSound(null)', '.setVibrate(null)',
        'channel.setSound(null, null)', 'channel.enableVibration(false)']) {
        assert.ok(patch.includes(setting), setting);
    }
    assert.match(patch, /android.sourceSets.main.java.setSrcDirs\(\[generated\]\)/);
    assert.match(patch, /dependsOn\(patchTask\)/);
    assert.match(patch, /lines.count\(builderAnchor\) != 1/);
    assert.match(patch, /lines.count\(channelAnchor\) != 1/);
    assert.match(patch, /throw new GradleException/);
});

test('foreground service and media controls are retained across pauses', () => {
    assert.match(read('lib/main.dart'), /androidStopForegroundOnPause: false/);
    assert.match(read('android/app/src/main/AndroidManifest.xml'),
        /android:foregroundServiceType="mediaPlayback"/);
    assert.match(read('lib/service/tts/tts_handler.dart'),
        /androidWillPauseWhenDucked: true/);
});
