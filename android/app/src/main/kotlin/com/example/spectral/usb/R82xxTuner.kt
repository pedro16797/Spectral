package com.example.spectral.usb

import android.util.Log

/**
 * Rafael Micro R820T/R820T2/R828D tuner driver.
 *
 * Transcribed from librtlsdr's `src/tuner_r82xx.c`. The magic tables below
 * (init array, band-switching ranges, gain steps) are hardware constants — if
 * a first bring-up misbehaves, diff them against that file before anything
 * else.
 *
 * Covers essentially every dongle sold as a branded "RTL-SDR". The FC0013
 * found in cheaper generic sticks has its own driver ([Fc0013Tuner]); E4000,
 * FC0012 and FC2580 are detected but rejected rather than half-supported.
 */
class R82xxTuner(
    private val rtl: Rtl2832u,
    private val i2cAddr: Int,
    private val isR828D: Boolean,
    override var xtalHz: Int,
) : RtlTunerDriver {
    companion object {
        private const val TAG = "R82xxTuner"

        private const val REG_SHADOW_START = 5
        private const val NUM_REGS = 32
        private const val VER_NUM = 49

        /** Register defaults for 0x05..0x1f. */
        private val INIT_ARRAY = intArrayOf(
            0x83, 0x32, 0x75,             // 05 to 07
            0xc0, 0x40, 0xd6, 0x6c,       // 08 to 0b
            0xf5, 0x63, 0x75, 0x68,       // 0c to 0f
            0x6c, 0x83, 0x80, 0x00,       // 10 to 13
            0x0f, 0x00, 0xc0, 0x30,       // 14 to 17
            0x48, 0xcc, 0x60, 0x00,       // 18 to 1b
            0x54, 0xae, 0x4a, 0xc0,       // 1c to 1f
        )

        /** Nibble bit-reversal LUT: the R82xx returns registers bit-reversed. */
        private val BITREV_LUT = intArrayOf(
            0x0, 0x8, 0x4, 0xc, 0x2, 0xa, 0x6, 0xe,
            0x1, 0x9, 0x5, 0xd, 0x3, 0xb, 0x7, 0xf,
        )

        private fun bitrev(b: Int): Int =
            ((BITREV_LUT[b and 0x0f] shl 4) or BITREV_LUT[(b shr 4) and 0x0f]) and 0xff

        private val LNA_GAIN_STEPS =
            intArrayOf(0, 9, 13, 40, 38, 13, 31, 22, 26, 31, 26, 14, 19, 5, 35, 13)
        private val MIXER_GAIN_STEPS =
            intArrayOf(0, 5, 10, 10, 19, 9, 10, 25, 17, 10, 8, 16, 13, 6, 3, -8)

        /** The RTL2832U's I2C bridge accepts at most 8 bytes per message. */
        private const val MAX_I2C_MSG_LEN = 8
    }

    /**
     * Band-switching table: for an LO frequency (MHz) at or above [freqMhz],
     * apply this open-drain / RF-mux / tracking-filter configuration.
     */
    private data class FreqRange(
        val freqMhz: Int,
        val openD: Int,
        val rfMuxPloy: Int,
        val tfC: Int,
        val xtalCap20p: Int,
        val xtalCap10p: Int,
        val xtalCap0p: Int,
    )

    private val freqRanges = listOf(
        FreqRange(0, 0x08, 0x02, 0xdf, 0x02, 0x01, 0x00),
        FreqRange(50, 0x08, 0x02, 0xbe, 0x02, 0x01, 0x00),
        FreqRange(55, 0x08, 0x02, 0x8b, 0x02, 0x01, 0x00),
        FreqRange(60, 0x08, 0x02, 0x7b, 0x02, 0x01, 0x00),
        FreqRange(65, 0x08, 0x02, 0x69, 0x02, 0x01, 0x00),
        FreqRange(70, 0x08, 0x02, 0x58, 0x02, 0x01, 0x00),
        FreqRange(75, 0x00, 0x02, 0x44, 0x02, 0x01, 0x00),
        FreqRange(80, 0x00, 0x02, 0x44, 0x02, 0x01, 0x00),
        FreqRange(90, 0x00, 0x02, 0x34, 0x02, 0x01, 0x00),
        FreqRange(100, 0x00, 0x02, 0x34, 0x02, 0x01, 0x00),
        FreqRange(110, 0x00, 0x02, 0x24, 0x02, 0x01, 0x00),
        FreqRange(120, 0x00, 0x02, 0x24, 0x02, 0x01, 0x00),
        FreqRange(140, 0x00, 0x02, 0x14, 0x02, 0x01, 0x00),
        FreqRange(180, 0x00, 0x02, 0x13, 0x02, 0x01, 0x00),
        FreqRange(220, 0x00, 0x02, 0x13, 0x02, 0x01, 0x00),
        FreqRange(250, 0x00, 0x02, 0x11, 0x02, 0x01, 0x00),
        FreqRange(280, 0x00, 0x02, 0x00, 0x02, 0x01, 0x00),
        FreqRange(310, 0x00, 0x41, 0x00, 0x02, 0x01, 0x00),
        FreqRange(450, 0x00, 0x41, 0x00, 0x02, 0x01, 0x00),
        FreqRange(588, 0x00, 0x40, 0x00, 0x02, 0x01, 0x00),
        FreqRange(650, 0x00, 0x40, 0x00, 0x02, 0x01, 0x00),
    )

    /** Shadow copy of registers 0x05..0x1f; the R82xx is write-only per-reg. */
    private val regs = IntArray(NUM_REGS)

    /** IF the tuner is configured to output, set by [setTvStandard]. */
    var intFreqHz: Int = Rtl2832u.R82XX_IF_FREQ
        private set

    override var hasLock: Boolean = false
        private set

    private var filCalCode: Int = 0
    private var input: Int = 0

    // ------------------------------------------------------------- reg I/O ---

    private fun writeRegs(startReg: Int, values: IntArray): Boolean {
        // Keep the shadow in sync so read-modify-write works without reading.
        for (i in values.indices) {
            val idx = startReg - REG_SHADOW_START + i
            if (idx in regs.indices) regs[idx] = values[i] and 0xff
        }

        var offset = 0
        var reg = startReg
        var remaining = values.size
        while (remaining > 0) {
            val size = minOf(remaining, MAX_I2C_MSG_LEN - 1)
            val buf = ByteArray(size + 1)
            buf[0] = (reg and 0xff).toByte()
            for (i in 0 until size) buf[i + 1] = (values[offset + i] and 0xff).toByte()
            if (!rtl.i2cWrite(i2cAddr, buf)) return false
            reg += size
            offset += size
            remaining -= size
        }
        return true
    }

    private fun writeReg(reg: Int, value: Int): Boolean =
        writeRegs(reg, intArrayOf(value))

    private fun readCache(reg: Int): Int {
        val idx = reg - REG_SHADOW_START
        return if (idx in regs.indices) regs[idx] else 0
    }

    /** Read-modify-write against the shadow registers. */
    private fun writeRegMask(reg: Int, value: Int, mask: Int): Boolean {
        val merged = (readCache(reg) and mask.inv()) or (value and mask)
        return writeReg(reg, merged and 0xff)
    }

    /**
     * Reads [len] registers starting at 0x00. The R82xx only supports
     * sequential reads from zero, and returns each byte bit-reversed.
     */
    private fun read(len: Int): IntArray? {
        val raw = rtl.i2cRead(i2cAddr, len) ?: return null
        return IntArray(len) { bitrev(raw[it].toInt() and 0xff) }
    }

    // ------------------------------------------------------------------ init ---

    /** Returns null on success, or the stage that failed. */
    override fun init(): String? {
        // Start from the documented register defaults.
        INIT_ARRAY.copyInto(regs)
        if (!writeRegs(REG_SHADOW_START, INIT_ARRAY)) {
            Log.e(TAG, "failed to write init array")
            return "could not write the tuner's initial register block over I2C"
        }
        setTvStandard()?.let { return it }
        if (!sysFreqSel()) return "system-frequency configuration failed"
        return null
    }

    // ------------------------------------------------------------------ mux ---

    private fun setMux(loFreqHz: Int): Boolean {
        val freqMhz = loFreqHz / 1_000_000
        var range = freqRanges[0]
        for (i in 0 until freqRanges.size - 1) {
            if (freqMhz < freqRanges[i + 1].freqMhz) {
                range = freqRanges[i]
                break
            }
            range = freqRanges[i + 1]
        }

        var ok = writeRegMask(0x17, range.openD, 0x08)      // open drain
        ok = writeRegMask(0x1a, range.rfMuxPloy, 0xc3) && ok // RF mux / polymux
        ok = writeReg(0x1b, range.tfC) && ok                 // tracking filter band
        // XTAL cap & drive: high-cap 0pF, matching librtlsdr's default.
        ok = writeRegMask(0x10, range.xtalCap0p, 0x0b) && ok
        ok = writeRegMask(0x08, 0x00, 0x3f) && ok
        ok = writeRegMask(0x09, 0x00, 0x3f) && ok
        return ok
    }

    // ------------------------------------------------------------------ PLL ---

    private fun setPll(freqHz: Int): Boolean {
        val vcoMin = 1_770_000L // kHz
        val vcoMax = vcoMin * 2

        var pllRef = xtalHz
        var refdiv2 = 0x00
        if (isR828D) {
            // The R828D halves the reference.
            pllRef /= 2
            refdiv2 = 0x10
        }
        val pllRefKhz = (pllRef + 500) / 1000
        val freqKhz = ((freqHz.toLong() + 500) / 1000)

        var ok = writeRegMask(0x10, refdiv2, 0x10)
        ok = writeRegMask(0x1a, 0x00, 0x0c) && ok // pll autotune = 128 kHz
        ok = writeRegMask(0x12, 0x80, 0xe0) && ok // VCO current = 100

        // Pick the mixer divider that lands the VCO in range.
        var mixDiv = 2
        var divNum = 0
        while (mixDiv <= 64) {
            if (freqKhz * mixDiv >= vcoMin && freqKhz * mixDiv < vcoMax) {
                var divBuf = mixDiv
                while (divBuf > 2) {
                    divBuf = divBuf shr 1
                    divNum++
                }
                break
            }
            mixDiv = mixDiv shl 1
        }

        val data = read(5) ?: return false
        val vcoPowerRef = if (isR828D) 1 else 2
        val vcoFineTune = (data[4] and 0x30) shr 4
        if (vcoFineTune > vcoPowerRef) divNum -= 1
        else if (vcoFineTune < vcoPowerRef) divNum += 1
        ok = writeRegMask(0x10, divNum shl 5, 0xe0) && ok

        val vcoFreq = freqHz.toLong() * mixDiv
        val nint = (vcoFreq / (2L * pllRef)).toInt()
        var vcoFra = ((vcoFreq - 2L * pllRef * nint) / 1000L) // kHz

        if (nint > (128 / vcoPowerRef) - 1) {
            Log.e(TAG, "PLL: no valid integer divider for ${freqHz} Hz")
            hasLock = false
            return false
        }

        val ni = (nint - 13) / 4
        val si = nint - 4 * ni - 13
        ok = writeReg(0x14, (ni + (si shl 6)) and 0xff) && ok

        // pw_sdm: power down the sigma-delta modulator on an exact integer N.
        ok = writeRegMask(0x12, if (vcoFra == 0L) 0x08 else 0x00, 0x08) && ok

        // Successive approximation of the fractional part.
        var nSdm = 2L
        var sdm = 0L
        while (vcoFra > 1) {
            if (vcoFra > 2 * pllRefKhz / nSdm) {
                sdm += 32768 / (nSdm / 2)
                vcoFra -= 2 * pllRefKhz / nSdm
                if (nSdm >= 0x8000) break
            }
            nSdm = nSdm shl 1
        }

        ok = writeReg(0x16, ((sdm shr 8) and 0xff).toInt()) && ok
        ok = writeReg(0x15, (sdm and 0xff).toInt()) && ok

        // Give the PLL two chances to lock, bumping VCO current in between.
        var locked = false
        for (attempt in 0 until 2) {
            val status = read(3) ?: return false
            if (status[2] and 0x40 != 0) {
                locked = true
                break
            }
            if (attempt == 0) writeRegMask(0x12, 0x60, 0xe0)
        }

        hasLock = locked
        if (!locked) {
            Log.w(TAG, "PLL did not lock at $freqHz Hz")
            return false
        }

        // pll autotune = 8 kHz
        return writeRegMask(0x1a, 0x08, 0x08) && ok
    }

    // ----------------------------------------------------------------- tune ---

    override fun setFreq(freqHz: Int): Boolean {
        val loFreq = freqHz + intFreqHz
        if (!setMux(loFreq)) return false
        if (!setPll(loFreq) || !hasLock) return false

        if (isR828D) {
            // Switch between the 'Cable1' and 'Air-In' inputs at 345 MHz,
            // where the noise floor matches for identical LNA settings.
            val airCable1In = if (freqHz > 345_000_000) 0x00 else 0x60
            if (airCable1In != input) {
                input = airCable1In
                return writeRegMask(0x05, airCable1In, 0x60)
            }
        }
        return true
    }

    // ------------------------------------------------------- standard/filter ---

    /**
     * Configures the channel filter for the < 6 MHz case used by SDR, running
     * the filter calibration that determines [filCalCode].
     */
    private fun setTvStandard(): String? {
        val ifKhz = 3570
        val filtCalLo = 56_000 // kHz
        val filtGain = 0x10    // +3 dB, 6 MHz on
        val imgR = 0x00        // image negative
        val filtQ = 0x10       // low Q
        val hpCorner = 0x6b    // 1.7 MHz disable, +2cap, 1.0 MHz
        val extEnable = 0x60
        val loopThrough = 0x00
        val ltAtt = 0x00
        val fltExtWidest = 0x00
        val polyfilCur = 0x60

        // Restore the register defaults before calibrating.
        INIT_ARRAY.copyInto(regs)

        var ok = writeRegMask(0x0c, 0x00, 0x0f)
        ok = writeRegMask(0x13, VER_NUM, 0x3f) && ok
        // For LT gain test (digital TV path).
        ok = writeRegMask(0x1d, 0x00, 0x38) && ok
        Thread.sleep(1)

        intFreqHz = ifKhz * 1000

        // Filter calibration: two attempts, as the first can return a
        // saturated code on a cold device.
        for (attempt in 0 until 2) {
            writeRegMask(0x0b, hpCorner, 0x60) // set filt_cap
            writeRegMask(0x0f, 0x04, 0x04)     // cali clk on
            writeRegMask(0x10, 0x00, 0x03)     // XTAL cap 0pF for PLL

            if (!setPll(filtCalLo * 1000) || !hasLock) {
                Log.e(TAG, "filter calibration: PLL failed to lock")
                return "the PLL did not lock during filter calibration " +
                    "(attempt ${attempt + 1} at ${filtCalLo / 1000} MHz)"
            }

            writeRegMask(0x0b, 0x10, 0x10)     // start trigger
            Thread.sleep(1)
            writeRegMask(0x0b, 0x00, 0x10)     // stop trigger
            writeRegMask(0x0f, 0x00, 0x04)     // cali clk off

            val data = read(5)
                ?: return "could not read back the filter calibration result"
            filCalCode = data[4] and 0x0f
            if (filCalCode != 0 && filCalCode != 0x0f) break
        }
        // 0x0f means the calibration railed; fall back to the narrowest filter.
        if (filCalCode == 0x0f) filCalCode = 0

        ok = writeRegMask(0x0a, filtQ or filCalCode, 0x1f) && ok
        ok = writeRegMask(0x0b, hpCorner, 0xef) && ok      // BW, filter gain, HP corner
        ok = writeRegMask(0x07, imgR, 0x80) && ok          // image rejection
        ok = writeRegMask(0x06, filtGain, 0x30) && ok      // filt_3dB, V6MHz
        ok = writeRegMask(0x1e, extEnable, 0x60) && ok     // channel filter extension
        ok = writeRegMask(0x05, loopThrough, 0x80) && ok
        ok = writeRegMask(0x1f, ltAtt, 0x80) && ok
        ok = writeRegMask(0x0f, fltExtWidest, 0x80) && ok
        ok = writeRegMask(0x19, polyfilCur, 0x60) && ok    // RF poly filter current
        return if (ok) null else "writing the channel-filter registers failed"
    }

    /** Applies the DVB-T system settings librtlsdr uses for SDR operation. */
    private fun sysFreqSel(): Boolean {
        val mixerTop = 0x24
        val lnaTop = 0xe5
        val cpCur = 0x38
        val divBufCur = 0x30
        val lnaVthL = 0x53
        val mixerVthL = 0x75
        val airCable1In = 0x00
        val cable2In = 0x00
        val lnaDischarge = 14
        val filterCur = 0x40

        var ok = writeRegMask(0x1d, lnaTop, 0xc7)
        ok = writeRegMask(0x1c, mixerTop, 0xf8) && ok
        ok = writeReg(0x0d, lnaVthL) && ok
        ok = writeReg(0x0e, mixerVthL) && ok
        ok = writeRegMask(0x05, airCable1In, 0x60) && ok
        ok = writeRegMask(0x06, cable2In, 0x08) && ok
        ok = writeRegMask(0x11, cpCur, 0x38) && ok
        ok = writeRegMask(0x17, divBufCur, 0x30) && ok
        ok = writeRegMask(0x0a, filterCur, 0x60) && ok

        // Settle the AGC: drop the LNA to its lowest top, run the fast AGC
        // clock briefly, then restore. This is librtlsdr's digital-TV path.
        ok = writeRegMask(0x1d, 0x00, 0x38) && ok // LNA TOP lowest
        ok = writeRegMask(0x1c, 0x00, 0x04) && ok // normal mode
        ok = writeRegMask(0x06, 0x00, 0x40) && ok // PRE_DECT off
        ok = writeRegMask(0x1a, 0x30, 0x30) && ok // agc clk 250 Hz
        Thread.sleep(250)
        ok = writeRegMask(0x1d, 0x18, 0x38) && ok // LNA TOP = 3
        ok = writeRegMask(0x1c, mixerTop, 0x04) && ok
        ok = writeRegMask(0x1e, lnaDischarge, 0x1f) && ok
        ok = writeRegMask(0x1a, 0x20, 0x30) && ok // agc clk 60 Hz
        return ok
    }

    // ------------------------------------------------------------------ gain ---

    /**
     * [manual] false enables the tuner's own LNA/mixer AGC. When true,
     * [gainTenthsDb] is matched by walking the LNA and mixer gain steps, the
     * same approximation librtlsdr uses.
     */
    override fun setGain(manual: Boolean, gainTenthsDb: Int): Boolean {
        if (!manual) {
            var ok = writeRegMask(0x05, 0x00, 0x10)  // LNA auto
            ok = writeRegMask(0x07, 0x10, 0x10) && ok // mixer auto
            ok = writeRegMask(0x0c, 0x0b, 0x9f) && ok // fixed VGA gain 16.3 dB
            return ok
        }

        var ok = writeRegMask(0x05, 0x10, 0x10)  // LNA manual
        ok = writeRegMask(0x07, 0x00, 0x10) && ok // mixer manual
        if (read(4) == null) return false
        ok = writeRegMask(0x0c, 0x08, 0x9f) && ok // fixed VGA gain 26.5 dB

        var totalGain = 0
        var lnaIndex = 0
        var mixIndex = 0
        for (i in 0 until 15) {
            if (totalGain >= gainTenthsDb) break
            totalGain += LNA_GAIN_STEPS[++lnaIndex]
            if (totalGain >= gainTenthsDb) break
            totalGain += MIXER_GAIN_STEPS[++mixIndex]
        }

        ok = writeRegMask(0x05, lnaIndex, 0x0f) && ok
        ok = writeRegMask(0x07, mixIndex, 0x0f) && ok
        return ok
    }
}
