package com.mousty.repbirds

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.tech.IsoDep
import android.os.Build
import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Push via FCM, without the Firebase Flutter plugins: hands the token to Dart
 * (`repbirds/push`, see lib/core/push/push_service.dart) and forwards tapped notifications.
 * Firebase only starts when android/app/google-services.json was present at build time.
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var pendingPermission: MethodChannel.Result? = null
    /** A tap that arrived before Dart asked for it (e.g. the push that launched the app). */
    private var pendingOpened: Map<String, Any?>? = null
    private var dartReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingOpened = openedMessage(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "repbirds/push")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestPermission(result)
                "getToken" -> getToken(result)
                "getInitialMessage" -> {
                    dartReady = true
                    result.success(pendingOpened)
                    pendingOpened = null
                }
                else -> result.notImplemented()
            }
        }
        this.channel = channel
        configureGymNfc(flutterEngine)
        PushMessagingService.listener = { method, arguments -> runOnUiThread { channel.invokeMethod(method, arguments) } }
    }

    /**
     * Gym card over NFC (`repbirds/gym_nfc`, see lib/core/gym/nfc_card.dart): stores the card
     * for [GymCardApduService], and at the gym's reception reads other phones' cards in reader mode.
     */
    private fun configureGymNfc(flutterEngine: FlutterEngine) {
        val nfc = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "repbirds/gym_nfc")
        nfc.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(NfcAdapter.getDefaultAdapter(this)?.isEnabled == true)
                "setCard" -> {
                    GymCardApduService.saveCard(this, call.argument<String>("card"))
                    result.success(null)
                }
                "clearCard" -> {
                    GymCardApduService.saveCard(this, null)
                    result.success(null)
                }
                "startReading" -> result.success(startReading())
                "stopReading" -> {
                    reading = false
                    NfcAdapter.getDefaultAdapter(this)?.disableReaderMode(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        gymNfc = nfc
    }

    private var gymNfc: MethodChannel? = null
    private var reading = false

    private fun startReading(): Boolean {
        val adapter = NfcAdapter.getDefaultAdapter(this) ?: return false
        if (!adapter.isEnabled) return false
        reading = true
        enableReader(adapter)
        return true
    }

    private fun enableReader(adapter: NfcAdapter) {
        val flags = NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK
        adapter.enableReaderMode(this, { tag ->
            val isoDep = IsoDep.get(tag) ?: return@enableReaderMode
            try {
                isoDep.connect()
                isoDep.timeout = 2000
                val response = isoDep.transceive(GymCardApduService.selectApdu())
                if (response.size > 2 && response.takeLast(2).toByteArray().contentEquals(GymCardApduService.SW_OK)) {
                    val code = String(response, 0, response.size - 2, Charsets.US_ASCII)
                    runOnUiThread { gymNfc?.invokeMethod("onCode", code) }
                }
            } catch (e: Exception) {
                // phone moved away mid-read: the next tap tries again
            } finally {
                try { isoDep.close() } catch (e: Exception) {}
            }
        }, flags, null)
    }

    // reader mode only lasts while the activity is in front
    override fun onResume() {
        super.onResume()
        if (reading) NfcAdapter.getDefaultAdapter(this)?.let { if (it.isEnabled) enableReader(it) }
    }

    override fun onPause() {
        if (reading) NfcAdapter.getDefaultAdapter(this)?.disableReaderMode(this)
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        gymNfc = null
        PushMessagingService.listener = null
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val message = openedMessage(intent) ?: return
        val channel = channel
        if (dartReady && channel != null) channel.invokeMethod("onOpened", message) else pendingOpened = message
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU
            || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }

    private fun getToken(result: MethodChannel.Result) {
        if (FirebaseApp.getApps(this).isEmpty()) {
            result.success(null) // built without google-services.json
            return
        }
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) result.success(task.result)
            else result.error("fcm", task.exception?.message, null)
        }
    }

    // A notification tapped while the app was in background: FCM puts its data in the extras.
    private fun openedMessage(intent: Intent?): Map<String, Any?>? {
        val extras = intent?.extras ?: return null
        if (!extras.containsKey("google.message_id")) return null
        val data = extras.keySet()
            .filter { !it.startsWith("google.") && !it.startsWith("gcm.") && it != "from" && it != "collapse_key" }
            .associateWith { extras.getString(it) }
        intent.removeExtra("google.message_id") // handled once, not again on recreate
        return mapOf("data" to data)
    }

    private companion object {
        const val PERMISSION_REQUEST = 4210
    }
}
