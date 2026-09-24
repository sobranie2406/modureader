package xyz.luan.audioplayers.player

import android.media.MediaPlayer
import android.os.Build
import android.os.PowerManager
import xyz.luan.audioplayers.AudioContextAndroid
import xyz.luan.audioplayers.source.Source

class MediaPlayerWrapper(
    private val wrappedPlayer: WrappedPlayer,
) : PlayerWrapper {
    private val mediaPlayer = createMediaPlayer(wrappedPlayer)

    private fun createMediaPlayer(wrappedPlayer: WrappedPlayer): MediaPlayer {
        val mediaPlayer = MediaPlayer().apply {
            setOnPreparedListener { wrappedPlayer.onPrepared() }
            setOnCompletionListener { wrappedPlayer.onCompletion() }
            setOnSeekCompleteListener { wrappedPlayer.onSeekComplete() }
            setOnErrorListener { _, what, extra -> wrappedPlayer.onError(what, extra) }
            setOnBufferingUpdateListener { _, percent -> wrappedPlayer.onBuffering(percent) }
        }
        wrappedPlayer.context.setAttributesOnPlayer(mediaPlayer)
        // Dart may set the context before the native player is lazily created;
        // updateContext() will then never run for this instance.
        if (wrappedPlayer.context.stayAwake) {
            mediaPlayer.setWakeMode(wrappedPlayer.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
        }
        return mediaPlayer
    }

    override fun getDuration(): Int? {
        // media player returns -1 if the duration is unknown
        return mediaPlayer.duration.takeUnless { it == -1 }
    }

    override fun getCurrentPosition(): Int {
        return mediaPlayer.currentPosition
    }

    override fun setVolume(leftVolume: Float, rightVolume: Float) {
        mediaPlayer.setVolume(leftVolume, rightVolume)
    }

    override fun setRate(rate: Float) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            mediaPlayer.playbackParams = mediaPlayer.playbackParams.setSpeed(rate)
        } else if (rate == 1.0f) {
            mediaPlayer.start()
        } else {
            error("Changing the playback rate is only available for Android M/23+ or using LOW_LATENCY mode.")
        }
    }

    override fun setSource(source: Source) {
        reset()
        source.setForMediaPlayer(mediaPlayer)
    }

    override fun setLooping(looping: Boolean) {
        mediaPlayer.isLooping = looping
    }

    override fun start() {
        setRate(wrappedPlayer.rate)
        // setPlaybackParams can start native audio without the Java start()
        // bookkeeping. Explicitly start to report PLAYER_STATE_STARTED to
        // AudioService (media-key routing) and acquire the configured wake lock.
        // Calling start on an already started MediaPlayer is safe.
        mediaPlayer.start()
    }

    override fun pause() {
        mediaPlayer.pause()
    }

    override fun stop() {
        mediaPlayer.stop()
    }

    override fun release() {
        mediaPlayer.reset()
        mediaPlayer.release()
    }

    override fun seekTo(position: Int) {
        mediaPlayer.seekTo(position)
    }

    override fun updateContext(context: AudioContextAndroid) {
        context.setAttributesOnPlayer(mediaPlayer)
        if (context.stayAwake) {
            mediaPlayer.setWakeMode(wrappedPlayer.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
        }
    }

    override fun prepare() {
        mediaPlayer.prepareAsync()
    }

    override fun reset() {
        mediaPlayer.reset()
    }

    override fun isLiveStream(): Boolean {
        val duration = getDuration()
        return duration == null || duration == 0
    }
}
