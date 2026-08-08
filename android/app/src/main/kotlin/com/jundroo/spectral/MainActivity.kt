package com.jundroo.spectral

import android.content.Intent
import com.jundroo.spectral.usb.SpectralUsbBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var usbBridge: SpectralUsbBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = SpectralUsbBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        bridge.start()
        usbBridge = bridge
        // The activity may have been launched by USB_DEVICE_ATTACHED; replay
        // that intent so the app can offer to set the dongle up immediately.
        bridge.handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // launchMode is singleTop, so an attach while the app is already
        // running arrives here rather than through configureFlutterEngine.
        usbBridge?.handleIntent(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        usbBridge?.stop()
        usbBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
