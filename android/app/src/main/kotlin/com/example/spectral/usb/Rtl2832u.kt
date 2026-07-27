package com.example.spectral.usb

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.util.Log

/**
 * RTL2832U demodulator driver over Android's [UsbDeviceConnection].
 *
 * Register access follows librtlsdr (`src/librtlsdr.c`): vendor control
 * transfers carry the register address in wValue and the register block in
 * wIndex, with bit 4 of the block byte set for writes. Sample data arrives as
 * unsigned-8-bit interleaved I/Q on bulk endpoint 0x81.
 *
 * NOTE: this bring-up is transcribed from librtlsdr and has not been validated
 * against physical hardware in this repository. [Rtl2832u.selfTest] exists to
 * make a first bring-up on a real dongle diagnosable.
 */
class Rtl2832u(
    private val device: UsbDevice,
    private val connection: UsbDeviceConnection,
    private val usbInterface: UsbInterface,
    private val bulkIn: UsbEndpoint,
) {
    companion object {
        private const val TAG = "Rtl2832u"

        private const val CTRL_TIMEOUT_MS = 300
        private const val CTRL_IN =
            UsbConstants.USB_DIR_IN or UsbConstants.USB_TYPE_VENDOR // 0xC0
        private const val CTRL_OUT =
            UsbConstants.USB_DIR_OUT or UsbConstants.USB_TYPE_VENDOR // 0x40

        // Register blocks, selected by the high byte of wIndex.
        const val BLOCK_DEMOD = 0
        const val BLOCK_USB = 1
        const val BLOCK_SYS = 2
        const val BLOCK_IIC = 6

        // USB block registers.
        private const val USB_SYSCTL = 0x2000
        private const val USB_EPA_CTL = 0x2148
        private const val USB_EPA_MAXPKT = 0x2158

        // SYS block registers.
        private const val DEMOD_CTL = 0x3000
        private const val DEMOD_CTL_1 = 0x300b

        /** Reference crystal on standard dongles (Hz). */
        const val RTL_XTAL_HZ = 28_800_000

        /** The R828D carries its own 16 MHz reference, unlike the R820T. */
        const val R828D_XTAL_HZ = 16_000_000

        /** IF the RTL2832U is programmed to when paired with an R82xx tuner. */
        const val R82XX_IF_FREQ = 3_570_000

        private const val E4K_I2C_ADDR = 0xc8
        private const val E4K_CHECK_ADDR = 0x02
        private const val E4K_CHECK_VAL = 0x40
        private const val FC0013_I2C_ADDR = 0xc6
        private const val FC0013_CHECK_ADDR = 0x00
        private const val FC0013_CHECK_VAL = 0xa3
        private const val R820T_I2C_ADDR = 0x34
        private const val R828D_I2C_ADDR = 0x74
        private const val R82XX_CHECK_ADDR = 0x00
        private const val R82XX_CHECK_VAL = 0x69

        /** Default baseband FIR (8 x int8 then 8 x int12), from librtlsdr. */
        private val FIR_DEFAULT = intArrayOf(
            -54, -36, -41, -40, -32, -14, 14, 53,
            101, 156, 215, 273, 327, 372, 404, 421,
        )
    }

    /** Tuner detected during [open]. */
    var tuner: RtlTuner = RtlTuner.NONE
        private set

    private var tunerDriver: RtlTunerDriver? = null

    /**
     * The tuner's own reference crystal, before PPM correction. Most dongles
     * share the RTL2832U's 28.8 MHz, but the R828D does not.
     */
    private var tunerXtalHz: Int = RTL_XTAL_HZ

    /** PPM correction currently applied to both the RTL and tuner clocks. */
    private var ppm: Int = 0
    private var centerFreqHz: Int = 100_000_000
    private var sampleRateHz: Int = 2_048_000

    val deviceName: String get() = device.deviceName

    // ---------------------------------------------------------------- I/O ---

    private fun writeArray(block: Int, addr: Int, data: ByteArray): Boolean {
        val index = (block shl 8) or 0x10
        val r = connection.controlTransfer(
            CTRL_OUT, 0, addr, index, data, data.size, CTRL_TIMEOUT_MS
        )
        if (r != data.size) {
            Log.w(TAG, "writeArray(block=$block addr=0x${addr.toString(16)}) -> $r")
            return false
        }
        return true
    }

    private fun readArray(block: Int, addr: Int, len: Int): ByteArray? {
        val index = block shl 8
        val buf = ByteArray(len)
        val r = connection.controlTransfer(
            CTRL_IN, 0, addr, index, buf, len, CTRL_TIMEOUT_MS
        )
        if (r != len) {
            Log.w(TAG, "readArray(block=$block addr=0x${addr.toString(16)}) -> $r")
            return null
        }
        return buf
    }

    /** Writes [len] (1 or 2) bytes, big-endian, to a non-demod register. */
    fun writeReg(block: Int, addr: Int, value: Int, len: Int): Boolean {
        val data = if (len == 1) {
            byteArrayOf((value and 0xff).toByte())
        } else {
            byteArrayOf(((value shr 8) and 0xff).toByte(), (value and 0xff).toByte())
        }
        return writeArray(block, addr, data)
    }

    fun readReg(block: Int, addr: Int, len: Int): Int {
        val data = readArray(block, addr, len) ?: return -1
        return if (len == 1) {
            data[0].toInt() and 0xff
        } else {
            ((data[0].toInt() and 0xff) shl 8) or (data[1].toInt() and 0xff)
        }
    }

    /**
     * Demodulator registers live behind a different addressing scheme: the
     * address goes in the high byte of wValue with 0x20 in the low byte, and
     * the page number goes in wIndex.
     */
    fun demodWriteReg(page: Int, addr: Int, value: Int, len: Int): Boolean {
        val index = 0x10 or page
        val wValue = (addr shl 8) or 0x20
        val data = if (len == 1) {
            byteArrayOf((value and 0xff).toByte())
        } else {
            byteArrayOf(((value shr 8) and 0xff).toByte(), (value and 0xff).toByte())
        }
        val r = connection.controlTransfer(
            CTRL_OUT, 0, wValue, index, data, data.size, CTRL_TIMEOUT_MS
        )
        // librtlsdr performs this dummy read after every demod write.
        demodReadReg(0x0a, 0x01, 1)
        if (r != len) {
            Log.w(TAG, "demodWriteReg(page=$page addr=0x${addr.toString(16)}) -> $r")
            return false
        }
        return true
    }

    fun demodReadReg(page: Int, addr: Int, len: Int): Int {
        val wValue = (addr shl 8) or 0x20
        val buf = ByteArray(len)
        val r = connection.controlTransfer(
            CTRL_IN, 0, wValue, page, buf, len, CTRL_TIMEOUT_MS
        )
        if (r != len) return -1
        // Assembled little-endian, matching librtlsdr's demod_read_reg.
        return if (len == 1) {
            buf[0].toInt() and 0xff
        } else {
            ((buf[1].toInt() and 0xff) shl 8) or (buf[0].toInt() and 0xff)
        }
    }

    // ---------------------------------------------------------------- I2C ---

    /**
     * The demodulator fronts the tuner's I2C bus. The repeater must be open
     * around every tuner access and closed afterwards, otherwise the
     * demodulator stops responding.
     */
    fun setI2cRepeater(on: Boolean): Boolean =
        demodWriteReg(1, 0x01, if (on) 0x18 else 0x10, 1)

    fun i2cWrite(i2cAddr: Int, data: ByteArray): Boolean =
        writeArray(BLOCK_IIC, i2cAddr, data)

    fun i2cRead(i2cAddr: Int, len: Int): ByteArray? =
        readArray(BLOCK_IIC, i2cAddr, len)

    private fun i2cReadReg(i2cAddr: Int, reg: Int): Int {
        if (!writeArray(BLOCK_IIC, i2cAddr, byteArrayOf((reg and 0xff).toByte()))) return -1
        val data = readArray(BLOCK_IIC, i2cAddr, 1) ?: return -1
        return data[0].toInt() and 0xff
    }

    // ------------------------------------------------------------ bring-up ---

    /**
     * Last raw values read while probing the I2C bus, so a failed probe can be
     * reported (and diagnosed) without attaching a debugger.
     */
    private var probeReport: String = ""

    /**
     * Runs the full open sequence.
     *
     * Returns null on success, or a human-readable reason for the failure —
     * the caller surfaces it in the UI, so it has to name the actual stage
     * rather than a generic "could not open".
     */
    fun open(): String? {
        if (!connection.claimInterface(usbInterface, true)) {
            Log.e(TAG, "claimInterface failed")
            return "Could not claim the USB interface. Another app may be " +
                "holding the dongle — unplug it, close other SDR apps, and retry."
        }
        initBaseband()

        // If the demodulator itself is not responding, every later stage will
        // fail confusingly. Check it before blaming the tuner.
        val demodCtl = readReg(BLOCK_SYS, DEMOD_CTL, 1)
        if (demodCtl < 0) {
            return "The RTL2832U demodulator is not responding to control " +
                "transfers (register read failed). The dongle may be faulty, " +
                "or the USB link may be unstable — try a different OTG cable."
        }

        tuner = probeTuner()
        Log.i(TAG, "Detected tuner: $tuner ($probeReport)")

        when (tuner) {
            RtlTuner.R820T, RtlTuner.R828D -> {
                // The R82xx runs a real IF rather than zero-IF.
                demodWriteReg(1, 0xb1, 0x1a, 1) // disable Zero-IF mode
                demodWriteReg(0, 0x08, 0x4d, 1) // only enable In-phase ADC input
                setIfFreq(R82XX_IF_FREQ)
                demodWriteReg(1, 0x15, 0x01, 1) // enable spectrum inversion

                val isR828D = tuner == RtlTuner.R828D
                if (isR828D) tunerXtalHz = R828D_XTAL_HZ
                val driver = R82xxTuner(
                    rtl = this,
                    i2cAddr = if (isR828D) R828D_I2C_ADDR else R820T_I2C_ADDR,
                    isR828D = isR828D,
                    xtalHz = tunerXtalHz,
                )
                setI2cRepeater(true)
                val failure = driver.init()
                setI2cRepeater(false)
                if (failure != null) {
                    Log.e(TAG, "R82xx tuner init failed: $failure")
                    return "$tuner tuner found, but initialisation failed: $failure"
                }
                tunerDriver = driver
            }
            RtlTuner.FC0013 -> {
                // The FC0013 runs the demodulator in zero-IF, which is exactly
                // what initBaseband() left it in — so unlike the R82xx branch
                // above, no IF-frequency or spectrum-inversion changes here.
                val driver = Fc0013Tuner(rtl = this, xtalHz = tunerXtalHz)
                setI2cRepeater(true)
                val failure = driver.init()
                setI2cRepeater(false)
                if (failure != null) {
                    Log.e(TAG, "FC0013 tuner init failed: $failure")
                    return "FC0013 tuner found, but initialisation failed: $failure"
                }
                tunerDriver = driver
            }
            RtlTuner.NONE -> {
                Log.e(TAG, "No supported tuner found on the I2C bus ($probeReport)")
                return "No tuner responded on the demodulator's I2C bus " +
                    "($probeReport). The demodulator is reachable, so this is " +
                    "most likely a driver bug rather than a hardware fault."
            }
            else -> {
                // E4000 / FC0012 / FC2580 need their own tuner drivers, which
                // this implementation does not provide.
                Log.e(TAG, "Tuner $tuner is not supported by this driver")
                return "Unsupported tuner ($tuner). This driver supports " +
                    "R820T/R820T2/R828D and FC0013 dongles; use the RTL-TCP " +
                    "source instead."
            }
        }

        setSampleRate(sampleRateHz)
        setCenterFrequency(centerFreqHz)
        setAgc(true)
        return null
    }

    private fun initBaseband() {
        // USB bring-up.
        writeReg(BLOCK_USB, USB_SYSCTL, 0x09, 1)
        writeReg(BLOCK_USB, USB_EPA_MAXPKT, 0x0002, 2)
        writeReg(BLOCK_USB, USB_EPA_CTL, 0x1002, 2)

        // Power on the demodulator.
        writeReg(BLOCK_SYS, DEMOD_CTL_1, 0x22, 1)
        writeReg(BLOCK_SYS, DEMOD_CTL, 0xe8, 1)

        // Soft-reset the demodulator (bit 3).
        demodWriteReg(1, 0x01, 0x14, 1)
        demodWriteReg(1, 0x01, 0x10, 1)

        // Disable spectrum inversion and adjacent-channel rejection.
        demodWriteReg(1, 0x15, 0x00, 1)
        demodWriteReg(1, 0x16, 0x0000, 2)

        // Clear the DDC shift and IF frequency registers.
        for (i in 0 until 6) demodWriteReg(1, 0x16 + i, 0x00, 1)

        setFir()

        // Enable SDR mode, disable DAGC (bit 5).
        demodWriteReg(0, 0x19, 0x05, 1)

        // Init the FSM state-holding register.
        demodWriteReg(1, 0x93, 0xf0, 1)
        demodWriteReg(1, 0x94, 0x0f, 1)

        // Disable the RF and IF AGC loops.
        demodWriteReg(1, 0x11, 0x00, 1)
        demodWriteReg(1, 0x04, 0x00, 1)

        // Disable the PID filter.
        demodWriteReg(0, 0x61, 0x60, 1)

        // opt_adc_iq = 0, default ADC_I/ADC_Q datapath.
        demodWriteReg(0, 0x06, 0x80, 1)

        // Enable zero-IF, DC cancellation and I/Q compensation/estimation.
        demodWriteReg(1, 0xb1, 0x1b, 1)

        // Disable the 4.096 MHz clock output on pin TP_CK0.
        demodWriteReg(0, 0x0d, 0x83, 1)
    }

    /** Packs the 8 x int8 + 8 x int12 FIR table and writes it to the demod. */
    private fun setFir() {
        val fir = IntArray(20)
        for (i in 0 until 8) fir[i] = FIR_DEFAULT[i] and 0xff
        var i = 0
        while (i < 8) {
            val v0 = FIR_DEFAULT[8 + i]
            val v1 = FIR_DEFAULT[8 + i + 1]
            fir[8 + i * 3 / 2] = (v0 shr 4) and 0xff
            fir[8 + i * 3 / 2 + 1] = ((v0 shl 4) or ((v1 shr 8) and 0x0f)) and 0xff
            fir[8 + i * 3 / 2 + 2] = v1 and 0xff
            i += 2
        }
        for (j in fir.indices) demodWriteReg(1, 0x1c + j, fir[j], 1)
    }

    private fun probeTuner(): RtlTuner {
        setI2cRepeater(true)
        try {
            // Read every candidate address up front so a failed probe can
            // report what each one actually returned, rather than just "none".
            val r820t = i2cReadReg(R820T_I2C_ADDR, R82XX_CHECK_ADDR)
            val r828d = i2cReadReg(R828D_I2C_ADDR, R82XX_CHECK_ADDR)
            val e4k = i2cReadReg(E4K_I2C_ADDR, E4K_CHECK_ADDR)
            val fc0013 = i2cReadReg(FC0013_I2C_ADDR, FC0013_CHECK_ADDR)

            probeReport = "R820T@0x34=${hex(r820t)} exp 0x69, " +
                "R828D@0x74=${hex(r828d)}, " +
                "E4K@0xc8=${hex(e4k)} exp 0x40, " +
                "FC0013@0xc6=${hex(fc0013)} exp 0xa3"

            return when {
                r820t == R82XX_CHECK_VAL -> RtlTuner.R820T
                r828d == R82XX_CHECK_VAL -> RtlTuner.R828D
                e4k == E4K_CHECK_VAL -> RtlTuner.E4000
                fc0013 == FC0013_CHECK_VAL -> RtlTuner.FC0013
                else -> RtlTuner.NONE
            }
        } finally {
            setI2cRepeater(false)
        }
    }

    /** Formats a register read for a diagnostic, distinguishing a failed read. */
    private fun hex(value: Int): String =
        if (value < 0) "read-failed" else "0x${value.toString(16).padStart(2, '0')}"

    // ------------------------------------------------------------- tuning ---

    /** RTL crystal frequency with the PPM correction applied. */
    private fun correctedXtal(): Double = RTL_XTAL_HZ * (1.0 + ppm / 1e6)

    /**
     * Programs the demodulator's DDC to down-convert the tuner's IF. The value
     * is negated because the RTL2832U shifts down by the programmed amount.
     */
    fun setIfFreq(freqHz: Int): Boolean {
        val ifFreq = -((freqHz.toDouble() * (1 shl 22) / correctedXtal())).toInt()
        var ok = demodWriteReg(1, 0x19, (ifFreq shr 16) and 0x3f, 1)
        ok = demodWriteReg(1, 0x1a, (ifFreq shr 8) and 0xff, 1) && ok
        ok = demodWriteReg(1, 0x1b, ifFreq and 0xff, 1) && ok
        return ok
    }

    fun setSampleRate(rateHz: Int): Boolean {
        // The resampler cannot produce rates in these gaps.
        if (rateHz <= 225_000 || rateHz > 3_200_000 ||
            (rateHz > 300_000 && rateHz <= 900_000)
        ) {
            Log.e(TAG, "Unsupported sample rate: $rateHz")
            return false
        }
        sampleRateHz = rateHz

        var ratio = ((RTL_XTAL_HZ.toDouble() * (1 shl 22)) / rateHz).toInt()
        ratio = ratio and 0x0ffffffc

        var ok = demodWriteReg(1, 0x9f, (ratio shr 16) and 0xffff, 2)
        ok = demodWriteReg(1, 0xa1, ratio and 0xffff, 2) && ok
        ok = setSampleFreqCorrection(ppm) && ok

        // Soft-reset the demodulator so the new ratio takes effect.
        ok = demodWriteReg(1, 0x01, 0x14, 1) && ok
        ok = demodWriteReg(1, 0x01, 0x10, 1) && ok
        return ok
    }

    private fun setSampleFreqCorrection(ppmValue: Int): Boolean {
        val offs = (-ppmValue.toDouble() * (1 shl 24) / 1_000_000.0).toInt()
        var ok = demodWriteReg(1, 0x3f, offs and 0xff, 1)
        ok = demodWriteReg(1, 0x3e, (offs shr 8) and 0x3f, 1) && ok
        return ok
    }

    fun setCenterFrequency(freqHz: Int): Boolean {
        centerFreqHz = freqHz
        val driver = tunerDriver ?: return false
        setI2cRepeater(true)
        val ok = driver.setFreq(freqHz)
        setI2cRepeater(false)
        return ok
    }

    /** Applies a PPM correction to both the RTL resampler and the tuner PLL. */
    fun setPpm(value: Int): Boolean {
        if (value == ppm) return true
        ppm = value
        var ok = setSampleFreqCorrection(ppm)
        // Correct the tuner against *its own* reference, not the RTL's.
        tunerDriver?.xtalHz = (tunerXtalHz * (1.0 + ppm / 1e6)).toInt()
        // Only the R82xx path runs a real IF; zero-IF tuners have none to move.
        if (tuner == RtlTuner.R820T || tuner == RtlTuner.R828D) {
            ok = setIfFreq(R82XX_IF_FREQ) && ok
        }
        // Retune so the new correction takes effect.
        ok = setCenterFrequency(centerFreqHz) && ok
        return ok
    }

    /** Enables tuner AGC + RTL2832 AGC (true) or a fixed manual gain (false). */
    fun setAgc(enabled: Boolean): Boolean {
        val driver = tunerDriver ?: return false
        setI2cRepeater(true)
        val ok = driver.setGain(manual = !enabled, gainTenthsDb = 0)
        setI2cRepeater(false)
        // RTL2832 digital AGC.
        return demodWriteReg(0, 0x19, if (enabled) 0x25 else 0x05, 1) && ok
    }

    /** Sets a manual tuner gain, in tenths of a dB. */
    fun setTunerGain(gainTenthsDb: Int): Boolean {
        val driver = tunerDriver ?: return false
        setI2cRepeater(true)
        val ok = driver.setGain(manual = true, gainTenthsDb = gainTenthsDb)
        setI2cRepeater(false)
        return ok
    }

    // ---------------------------------------------------------- streaming ---

    /** Flushes the endpoint FIFO. Must be called before the first bulk read. */
    fun resetBuffer(): Boolean {
        var ok = writeReg(BLOCK_USB, USB_EPA_CTL, 0x1002, 2)
        ok = writeReg(BLOCK_USB, USB_EPA_CTL, 0x0000, 2) && ok
        return ok
    }

    /**
     * Reads one chunk of interleaved unsigned-8-bit I/Q. Returns the number of
     * bytes read, or a negative value on error/timeout.
     */
    fun readSamples(buffer: ByteArray, timeoutMs: Int): Int =
        connection.bulkTransfer(bulkIn, buffer, buffer.size, timeoutMs)

    /**
     * Reads back a handful of registers so a first bring-up against real
     * hardware can be diagnosed from `adb logcat` without a debugger.
     */
    fun selfTest(): Map<String, Any> {
        val demodCtl = readReg(BLOCK_SYS, DEMOD_CTL, 1)
        val usbSysctl = readReg(BLOCK_USB, USB_SYSCTL, 1)
        val fsm = demodReadReg(1, 0x93, 1)
        return mapOf(
            "tuner" to tuner.name,
            "demodCtl" to demodCtl,
            "usbSysctl" to usbSysctl,
            "fsmState" to fsm,
            "pllLocked" to (tunerDriver?.hasLock ?: false),
            "sampleRate" to sampleRateHz,
            "centerFrequency" to centerFreqHz,
            "ppm" to ppm,
        )
    }

    fun close() {
        try {
            // Power down the demodulator so the next open starts clean.
            writeReg(BLOCK_SYS, DEMOD_CTL, 0x20, 1)
            connection.releaseInterface(usbInterface)
        } catch (e: Exception) {
            Log.w(TAG, "close: $e")
        } finally {
            connection.close()
        }
    }
}

enum class RtlTuner { NONE, E4000, FC0012, FC0013, FC2580, R820T, R828D }
