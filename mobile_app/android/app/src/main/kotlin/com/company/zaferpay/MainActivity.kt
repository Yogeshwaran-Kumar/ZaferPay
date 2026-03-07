package com.company.zaferpay

import android.media.AudioManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.company.zaferpay/security"
    private val TAG = "ZaferPayCallDetect"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "secureScreen" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "unsecureScreen" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "checkCallState" -> {
                    result.success(isDeviceOnCall())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * Uses THREE independent methods to detect active calls.
     * If ANY method detects a call, returns true.
     * This ensures maximum device compatibility.
     */
    private fun isDeviceOnCall(): Boolean {
        var onCall = false

        // Method 1: AudioManager — NO PERMISSION NEEDED
        // This is the most reliable cross-device check.
        try {
            val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            val mode = audioManager.mode
            if (mode == AudioManager.MODE_IN_CALL || mode == AudioManager.MODE_IN_COMMUNICATION) {
                Log.d(TAG, "AudioManager detected call (mode=$mode)")
                onCall = true
            }
        } catch (e: Exception) {
            Log.e(TAG, "AudioManager check failed: ${e.message}")
        }

        // Method 2: TelecomManager.isInCall (Android S+, needs READ_PHONE_STATE)
        if (!onCall && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            try {
                val context = this.applicationContext
                if (androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.READ_PHONE_STATE) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    val telecomManager = context.getSystemService(android.content.Context.TELECOM_SERVICE) as android.telecom.TelecomManager
                    if (telecomManager.isInCall) {
                        Log.d(TAG, "TelecomManager detected call")
                        onCall = true
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "TelecomManager check failed: ${e.message}")
            }
        }

        // Method 3: TelephonyManager.callState (legacy, works on all Android versions)
        if (!onCall) {
            try {
                val telephonyManager = getSystemService(android.content.Context.TELEPHONY_SERVICE) as android.telephony.TelephonyManager
                @Suppress("DEPRECATION")
                val callState = telephonyManager.callState
                if (callState != android.telephony.TelephonyManager.CALL_STATE_IDLE) {
                    Log.d(TAG, "TelephonyManager detected call (state=$callState)")
                    onCall = true
                }
            } catch (e: Exception) {
                Log.e(TAG, "TelephonyManager check failed: ${e.message}")
            }
        }

        Log.d(TAG, "isDeviceOnCall => $onCall")
        return onCall
    }
}
