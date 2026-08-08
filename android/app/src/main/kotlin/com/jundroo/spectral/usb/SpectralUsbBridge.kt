package com.jundroo.spectral.usb

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Bridges the RTL-SDR USB driver to Dart.
 *
 * Three channels:
 *  - `spectral/sdr` (method): enumerate, permission, open/close, tuning.
 *  - `spectral/sdr/events` (event): attach / detach / permission results, so
 *    the app can react to hot-plug instead of only checking at startup.
 *  - `spectral/sdr/samples` (event): raw interleaved unsigned-8-bit I/Q.
 */
class SpectralUsbBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val TAG = "SpectralUsbBridge"
        private const val METHOD_CHANNEL = "spectral/sdr"
        private const val EVENT_CHANNEL = "spectral/sdr/events"
        private const val SAMPLE_CHANNEL = "spectral/sdr/samples"

        private const val ACTION_USB_PERMISSION = "com.jundroo.spectral.USB_PERMISSION"

        /** Bulk read size. Must be a multiple of the 512-byte USB packet. */
        private const val BULK_BUFFER_BYTES = 16384
        private const val BULK_TIMEOUT_MS = 1000

        /**
         * Maximum sample chunks queued to the platform thread before new ones
         * are dropped. Without a bound, main-thread jank lets the queue (and
         * heap) grow without limit at ~250 chunks/s.
         */
        private const val MAX_PENDING_CHUNKS = 8
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Serializes blocking USB control transfers off the platform thread. */
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "rtl-sdr-io")
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val sampleChannel = EventChannel(messenger, SAMPLE_CHANNEL)

    private var eventSink: EventChannel.EventSink? = null
    private var sampleSink: EventChannel.EventSink? = null

    @Volatile
    private var driver: Rtl2832u? = null
    private var streamThread: Thread? = null

    /**
     * Stop token owned by the *current* stream thread. Each thread gets its
     * own token so a stop that times out can never be undone by a subsequent
     * start (a shared flag allowed two readers on the same endpoint), and a
     * dying old thread cannot stop the new one.
     */
    @Volatile
    private var streaming = AtomicBoolean(false)

    /** Pending Dart result for an in-flight permission request. */
    private var pendingPermission: MethodChannel.Result? = null

    // ------------------------------------------------------------ receivers ---

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action != ACTION_USB_PERMISSION) return
            val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            // Never trust the broadcast extra: pre-33 the unprotected action is
            // spoofable, and the extra can be missing entirely. The USB service
            // is the authority on whether we actually hold permission.
            val granted = device != null && usbManager.hasPermission(device)
            Log.i(TAG, "USB permission ${if (granted) "granted" else "denied"} for ${device?.deviceName}")
            pendingPermission?.success(granted)
            pendingPermission = null
            emitEvent(
                mapOf(
                    "type" to "permission",
                    "granted" to granted,
                    "device" to (device?.let { describe(it) }),
                )
            )
        }
    }

    private val attachReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val device: UsbDevice = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE) ?: return
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> onDeviceAttached(device)
                UsbManager.ACTION_USB_DEVICE_DETACHED -> onDeviceDetached(device)
            }
        }
    }

    // ----------------------------------------------------------- lifecycle ---

    fun start() {
        methodChannel.setMethodCallHandler { call, result -> onMethodCall(call.method, call.arguments, result) }
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        sampleChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sampleSink = events
            }

            override fun onCancel(arguments: Any?) {
                sampleSink = null
            }
        })

        registerReceiverCompat(
            permissionReceiver, IntentFilter(ACTION_USB_PERMISSION), exported = false
        )
        registerReceiverCompat(
            attachReceiver,
            IntentFilter().apply {
                addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            },
            // ACTION_USB_DEVICE_* are protected system broadcasts.
            exported = true,
        )
    }

    fun stop() {
        // Tear the device down on the I/O thread — close() performs blocking
        // control transfers, and the executor already serializes all other
        // device access. shutdown() (not shutdownNow) lets it run first.
        ioExecutor.execute {
            stopStreaming()
            closeDevice()
        }
        ioExecutor.shutdown()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        sampleChannel.setStreamHandler(null)
        runCatching { context.unregisterReceiver(permissionReceiver) }
        runCatching { context.unregisterReceiver(attachReceiver) }
    }

    private fun registerReceiverCompat(
        receiver: BroadcastReceiver,
        filter: IntentFilter,
        exported: Boolean,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val flag = if (exported) Context.RECEIVER_EXPORTED else Context.RECEIVER_NOT_EXPORTED
            context.registerReceiver(receiver, filter, flag)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
    }

    /**
     * Handles the launch intent when Android starts the app because a matching
     * dongle was plugged in. Accepting that system dialog also grants USB
     * permission, so the app can go straight to opening the device.
     */
    fun handleIntent(intent: Intent?) {
        if (intent?.action != UsbManager.ACTION_USB_DEVICE_ATTACHED) return
        val device: UsbDevice = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE) ?: return
        Log.i(TAG, "Launched by USB attach: ${device.deviceName}")
        onDeviceAttached(device)
    }

    private fun onDeviceAttached(device: UsbDevice) {
        if (!RtlUsbIds.isKnownDongle(device.vendorId, device.productId)) return
        emitEvent(
            mapOf(
                "type" to "attached",
                "device" to describe(device),
            )
        )
    }

    private fun onDeviceDetached(device: UsbDevice) {
        if (!RtlUsbIds.isKnownDongle(device.vendorId, device.productId)) return
        if (driver?.deviceName == device.deviceName) {
            // On the I/O thread: teardown blocks (join + control transfers)
            // and must not race an in-flight open/tune on that executor.
            ioExecutor.execute {
                stopStreaming()
                closeDevice()
            }
        }
        emitEvent(
            mapOf(
                "type" to "detached",
                "device" to describe(device),
            )
        )
    }

    private fun emitEvent(payload: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(payload) }
    }

    // -------------------------------------------------------------- methods ---

    private fun onMethodCall(method: String, args: Any?, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val map = args as? Map<String, Any?> ?: emptyMap()

        when (method) {
            // Cheap, non-blocking: answer straight from the USB service.
            "listDevices" -> result.success(listDevices())
            // Completes when the system permission broadcast arrives.
            "requestPermission" -> requestPermission(map["deviceName"] as? String, result)

            // Everything below performs blocking USB control transfers, so it
            // must not run on the platform thread.
            "open" -> runOnIo(method, result) { openDevice(map) }
            "close" -> runOnIo(method, result) {
                stopStreaming()
                closeDevice()
                true
            }
            "startStream" -> runOnIo(method, result) { startStreaming() }
            "stopStream" -> runOnIo(method, result) {
                stopStreaming()
                true
            }
            "setFrequency" -> runOnIo(method, result) {
                driver?.setCenterFrequency((map["hz"] as Number).toInt()) ?: false
            }
            "setSampleRate" -> runOnIo(method, result) {
                driver?.setSampleRate((map["hz"] as Number).toInt()) ?: false
            }
            "setPpm" -> runOnIo(method, result) {
                driver?.setPpm((map["ppm"] as Number).toInt()) ?: false
            }
            "setAgc" -> runOnIo(method, result) {
                driver?.setAgc(map["enabled"] as? Boolean ?: true) ?: false
            }
            "setTunerGain" -> runOnIo(method, result) {
                driver?.setTunerGain((map["tenthsDb"] as Number).toInt()) ?: false
            }
            "selfTest" -> runOnIo(method, result) { driver?.selfTest() }
            else -> result.notImplemented()
        }
    }

    /**
     * Runs [block] on the USB I/O thread and delivers its outcome back on the
     * platform thread, which is where Flutter requires results to be sent.
     */
    private fun runOnIo(method: String, result: MethodChannel.Result, block: () -> Any?) {
        ioExecutor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                Log.e(TAG, "$method failed", e)
                mainHandler.post { result.error("sdr_error", e.message, null) }
            }
        }
    }

    private fun describe(device: UsbDevice): Map<String, Any?> = mapOf(
        "deviceName" to device.deviceName,
        "vendorId" to device.vendorId,
        "productId" to device.productId,
        "productName" to device.productName,
        "manufacturerName" to device.manufacturerName,
        "hasPermission" to usbManager.hasPermission(device),
        "supported" to RtlUsbIds.isKnownDongle(device.vendorId, device.productId),
    )

    /** Only ever returns dongles this driver knows how to talk to. */
    private fun listDevices(): List<Map<String, Any?>> =
        usbManager.deviceList.values
            .filter { RtlUsbIds.isKnownDongle(it.vendorId, it.productId) }
            .map { describe(it) }

    private fun findDevice(deviceName: String?): UsbDevice? {
        val devices = usbManager.deviceList.values
            .filter { RtlUsbIds.isKnownDongle(it.vendorId, it.productId) }
        // Fall back to the only attached dongle when Dart did not name one.
        return devices.firstOrNull { it.deviceName == deviceName } ?: devices.firstOrNull()
    }

    private fun requestPermission(deviceName: String?, result: MethodChannel.Result) {
        val device = findDevice(deviceName)
        if (device == null) {
            result.success(false)
            return
        }
        if (usbManager.hasPermission(device)) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result

        // The PendingIntent must be MUTABLE: UsbManager delivers its result by
        // filling in EXTRA_DEVICE/EXTRA_PERMISSION_GRANTED, which an immutable
        // intent silently discards — the grant then looks like a denial on
        // Android 12+. setPackage() below is the required mitigation.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        // Scoping the intent to this package keeps the NOT_EXPORTED receiver
        // reachable on Android 13+ and stops other apps from receiving it.
        val intent = Intent(ACTION_USB_PERMISSION).setPackage(context.packageName)
        val pending = PendingIntent.getBroadcast(context, 0, intent, flags)
        usbManager.requestPermission(device, pending)
    }

    /**
     * Opens the dongle and runs the bring-up.
     *
     * Always returns a map: on success the device description, on failure a
     * single `error` entry naming the stage that failed. Returning null for
     * every failure would force the UI to guess at the cause.
     */
    private fun openDevice(args: Map<String, Any?>): Map<String, Any?> {
        closeDevice()

        val device = findDevice(args["deviceName"] as? String) ?: run {
            Log.w(TAG, "open: no supported dongle attached")
            return failure("No supported RTL-SDR dongle is attached.")
        }
        if (!usbManager.hasPermission(device)) {
            Log.w(TAG, "open: no USB permission for ${device.deviceName}")
            return failure("USB permission has not been granted for this dongle.")
        }
        val connection = usbManager.openDevice(device) ?: run {
            Log.e(TAG, "open: openDevice returned null")
            return failure(
                "Android refused to open the dongle. Another app may be " +
                    "holding it — unplug it, close other SDR apps, and retry."
            )
        }

        // The RTL2832U exposes its sample stream on the first interface's
        // bulk IN endpoint (0x81 on every dongle seen in the wild).
        val usbInterface = device.getInterface(0)
        var bulkIn: UsbEndpoint? = null
        for (i in 0 until usbInterface.endpointCount) {
            val ep = usbInterface.getEndpoint(i)
            if (ep.direction == UsbConstants.USB_DIR_IN &&
                ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK
            ) {
                bulkIn = ep
                break
            }
        }
        if (bulkIn == null) {
            Log.e(TAG, "open: no bulk IN endpoint")
            connection.close()
            return failure("The dongle exposes no bulk IN endpoint for samples.")
        }

        val rtl = Rtl2832u(device, connection, usbInterface, bulkIn)
        val bringUpFailure = rtl.open()
        if (bringUpFailure != null) {
            rtl.close()
            return failure(bringUpFailure)
        }

        (args["sampleRate"] as? Number)?.let { rtl.setSampleRate(it.toInt()) }
        (args["ppm"] as? Number)?.let { rtl.setPpm(it.toInt()) }
        (args["frequency"] as? Number)?.let { rtl.setCenterFrequency(it.toInt()) }
        val gain = (args["tunerGainTenthsDb"] as? Number)?.toInt()
        if (gain == null) rtl.setAgc(true) else rtl.setTunerGain(gain)

        driver = rtl
        return describe(device) + mapOf("tuner" to rtl.tuner.name)
    }

    private fun failure(reason: String): Map<String, Any?> = mapOf("error" to reason)

    private fun closeDevice() {
        driver?.close()
        driver = null
    }

    // ------------------------------------------------------------ streaming ---

    private fun startStreaming(): Boolean {
        val rtl = driver ?: return false
        if (streaming.get() && streamThread?.isAlive == true) return true
        // Make sure any previous reader is fully gone before starting another.
        stopStreaming()

        rtl.resetBuffer()
        val active = AtomicBoolean(true)
        streaming = active
        val pendingChunks = AtomicInteger(0)
        val thread = Thread({
            val buffer = ByteArray(BULK_BUFFER_BYTES)
            var consecutiveErrors = 0
            while (active.get()) {
                val read = rtl.readSamples(buffer, BULK_TIMEOUT_MS)
                if (read <= 0) {
                    // A dropped read is normal at startup; a run of them means
                    // the device is gone or wedged.
                    if (++consecutiveErrors > 10) {
                        Log.e(TAG, "bulk read failed $consecutiveErrors times, stopping")
                        mainHandler.post {
                            eventSink?.success(mapOf("type" to "streamError"))
                        }
                        break
                    }
                    continue
                }
                consecutiveErrors = 0
                // Drop chunks when the platform thread falls behind rather
                // than queueing unbounded work against it.
                if (pendingChunks.get() >= MAX_PENDING_CHUNKS) continue
                pendingChunks.incrementAndGet()
                val chunk = buffer.copyOf(read)
                mainHandler.post {
                    pendingChunks.decrementAndGet()
                    sampleSink?.success(chunk)
                }
            }
            active.set(false)
        }, "rtl-sdr-bulk")
        thread.priority = Thread.MAX_PRIORITY
        thread.start()
        streamThread = thread
        return true
    }

    private fun stopStreaming() {
        streaming.set(false)
        // Wait at least one full bulk timeout: a shorter join can return while
        // the old thread is still blocked in readSamples.
        streamThread?.join(BULK_TIMEOUT_MS + 500L)
        streamThread = null
    }
}
