package bookingservice.tatos.tech

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var feedbackChannel: MethodChannel? = null
    private var successPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        feedbackChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "booking_os/feedback").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "playBookingSuccess") {
                    result.notImplemented()
                } else {
                    try {
                        playBookingSuccess()
                        result.success(null)
                    } catch (error: Exception) {
                        releaseSuccessPlayer()
                        result.error("AUDIO_UNAVAILABLE", "Booking sound could not play.", null)
                    }
                }
            }
        }
    }

    private fun playBookingSuccess() {
        releaseSuccessPlayer()
        val player = MediaPlayer()
        successPlayer = player
        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        resources.openRawResourceFd(R.raw.new_booking_bell).use { source ->
            player.setDataSource(source.fileDescriptor, source.startOffset, source.length)
        }
        player.isLooping = false
        player.setOnPreparedListener { ready ->
            if (successPlayer === ready) ready.start()
        }
        player.setOnCompletionListener { completed ->
            if (successPlayer === completed) releaseSuccessPlayer()
        }
        player.setOnErrorListener { failed, _, _ ->
            Log.w("BookingFeedback", "Success audio playback unavailable")
            if (successPlayer === failed) releaseSuccessPlayer()
            true
        }
        player.prepareAsync()
    }

    private fun releaseSuccessPlayer() {
        successPlayer?.release()
        successPlayer = null
    }

    override fun onDestroy() {
        feedbackChannel?.setMethodCallHandler(null)
        feedbackChannel = null
        releaseSuccessPlayer()
        super.onDestroy()
    }
}
