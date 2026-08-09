package gal.lendas.spectral.usb

import android.util.Log

/**
 * Fitipower FC0013 tuner driver.
 *
 * Transcribed from librtlsdr's `src/tuner_fc0013.c`. Common in cheaper
 * generic RTL2832U sticks, where the R820T family is the branded alternative.
 *
 * Unlike the R82xx, this chip leaves the demodulator in zero-IF — so
 * [Rtl2832u.open] deliberately skips the IF-frequency and spectrum-inversion
 * writes it performs for the R82xx, keeping the defaults from
 * `initBaseband()`.
 */
class Fc0013Tuner(
    private val rtl: Rtl2832u,
    override var xtalHz: Int,
) : RtlTunerDriver {
    companion object {
        private const val TAG = "Fc0013Tuner"

        /** 8-bit I2C address on the demodulator's bus. */
        private const val I2C_ADDR = 0xc6

        /** Register defaults for 0x00..0x15; index 0 is a dummy, never written. */
        private val INIT_REGS = intArrayOf(
            0x00, // 0x00 dummy
            0x09, // 0x01
            0x16, // 0x02
            0x00, // 0x03
            0x00, // 0x04
            0x17, // 0x05
            0x02, // 0x06 LPF bandwidth
            0x0a, // 0x07
            0xff, // 0x08 AGC clock /256, AGC gain 1/256, loop BW 1/8
            0x6e, // 0x09 LoopThrough disabled (0x6f enables it)
            0xb8, // 0x0a LO test buffer disabled
            0x82, // 0x0b
            0xfc, // 0x0c
            0x01, // 0x0d AGC not forcing, LNA forcing
            0x00, // 0x0e
            0x00, // 0x0f
            0x00, // 0x10
            0x00, // 0x11
            0x00, // 0x12
            0x00, // 0x13
            0x50, // 0x14 DVB-T high gain, UHF
            0x01, // 0x15
        )

        /**
         * LNA gain steps as (tenths of a dB, register value) pairs, ascending.
         * Selection picks the first entry at or above the requested gain.
         */
        private val LNA_GAINS = intArrayOf(
            -99, 0x02, -73, 0x03, -65, 0x05, -63, 0x04,
            -63, 0x00, -60, 0x07, -58, 0x01, -54, 0x06,
            58, 0x0f, 61, 0x0e, 63, 0x0d, 65, 0x0c,
            67, 0x0b, 68, 0x0a, 70, 0x09, 71, 0x08,
            179, 0x17, 181, 0x16, 182, 0x15, 184, 0x14,
            186, 0x13, 188, 0x12, 191, 0x11, 197, 0x10,
        )

        /** librtlsdr drives the FC0013 with the 6 MHz DVB-T channel filter. */
        private const val CHANNEL_BANDWIDTH_HZ = 6_000_000

        /** Above this VCO frequency the high VCO band is selected. */
        private const val VCO_HIGH_BAND_HZ = 3_060_000_000L
    }

    override var hasLock: Boolean = false
        private set

    // ---------------------------------------------------------------- I/O ---

    private fun writeReg(reg: Int, value: Int): Boolean = rtl.i2cWrite(
        I2C_ADDR,
        byteArrayOf((reg and 0xff).toByte(), (value and 0xff).toByte()),
    )

    /** Returns the register value, or -1 if the transfer failed. */
    private fun readReg(reg: Int): Int = rtl.i2cReadReg(I2C_ADDR, reg)

    // --------------------------------------------------------------- init ---

    override fun init(): String? {
        val regs = INIT_REGS.copyOf()
        regs[0x07] = regs[0x07] or 0x20 // enable clock output
        regs[0x0c] = regs[0x0c] or 0x02 // dual-master mode

        for (i in 1 until regs.size) {
            if (!writeReg(i, regs[i])) {
                return "could not write tuner register 0x${i.toString(16)}"
            }
        }
        return null
    }

    // --------------------------------------------------------------- tune ---

    /** Selects the VHF tracking filter band for [freqHz]. */
    private fun setVhfTrack(freqHz: Int): Boolean {
        val current = readReg(0x1d)
        if (current < 0) return false
        val track = when {
            freqHz <= 177_500_000 -> 0x1c // VHF track 7
            freqHz <= 184_500_000 -> 0x18 // 6
            freqHz <= 191_500_000 -> 0x14 // 5
            freqHz <= 198_500_000 -> 0x10 // 4
            freqHz <= 205_500_000 -> 0x0c // 3
            freqHz <= 219_500_000 -> 0x08 // 2
            freqHz < 300_000_000 -> 0x04 // 1
            else -> 0x1c // UHF and GPS
        }
        return writeReg(0x1d, (current and 0xe3) or track)
    }

    /** Routes the input through the VHF, UHF or GPS front-end path. */
    private fun setBandPath(freqHz: Int): Boolean {
        val r07 = readReg(0x07)
        if (r07 < 0) return false
        val r14 = readReg(0x14)
        if (r14 < 0) return false

        return when {
            freqHz < 300_000_000 ->
                // Enable the VHF filter; disable UHF and GPS.
                writeReg(0x07, r07 or 0x10) && writeReg(0x14, r14 and 0x1f)
            freqHz <= 862_000_000 ->
                // Disable the VHF filter; enable UHF.
                writeReg(0x07, r07 and 0xef) && writeReg(0x14, (r14 and 0x1f) or 0x40)
            else ->
                // Disable the VHF filter; enable GPS.
                writeReg(0x07, r07 and 0xef) && writeReg(0x14, (r14 and 0x1f) or 0x20)
        }
    }

    override fun setFreq(freqHz: Int): Boolean {
        hasLock = false
        val xtalDiv2 = xtalHz / 2
        if (xtalDiv2 <= 0) return false

        if (!setVhfTrack(freqHz)) return false
        if (!setBandPath(freqHz)) return false

        // Pick the VCO multiplier that lands f_vco in the usable band.
        val multi: Int
        var reg5: Int
        var reg6: Int
        when {
            freqHz < 37_084_000 -> { multi = 96; reg5 = 0x82; reg6 = 0x00 }
            freqHz < 55_625_000 -> { multi = 64; reg5 = 0x02; reg6 = 0x02 }
            freqHz < 74_167_000 -> { multi = 48; reg5 = 0x42; reg6 = 0x00 }
            freqHz < 111_250_000 -> { multi = 32; reg5 = 0x82; reg6 = 0x02 }
            freqHz < 148_334_000 -> { multi = 24; reg5 = 0x22; reg6 = 0x00 }
            freqHz < 222_500_000 -> { multi = 16; reg5 = 0x42; reg6 = 0x02 }
            freqHz < 296_667_000 -> { multi = 12; reg5 = 0x12; reg6 = 0x00 }
            freqHz < 445_000_000 -> { multi = 8; reg5 = 0x22; reg6 = 0x02 }
            freqHz < 593_334_000 -> { multi = 6; reg5 = 0x0a; reg6 = 0x00 }
            freqHz < 950_000_000 -> { multi = 4; reg5 = 0x12; reg6 = 0x02 }
            else -> { multi = 2; reg5 = 0x0a; reg6 = 0x02 }
        }

        // Long arithmetic throughout: f_vco reaches ~3.8 GHz, past Int range.
        val fVco = freqHz.toLong() * multi
        var vcoSelect = false
        if (fVco >= VCO_HIGH_BAND_HZ) {
            reg6 = reg6 or 0x08
            vcoSelect = true
        }

        // Integer part of the divider, rounded to nearest.
        val quotient = (fVco / xtalDiv2).toInt()
        var xdiv = quotient
        if (fVco - xdiv.toLong() * xtalDiv2 >= xtalDiv2 / 2) xdiv++

        var pm = xdiv / 8
        var am = xdiv - 8 * pm
        if (am < 2) {
            am += 8
            pm--
        }

        val reg1: Int
        val reg2: Int
        if (pm > 31) {
            reg1 = am + 8 * (pm - 31)
            reg2 = 31
        } else {
            reg1 = am
            reg2 = pm
        }
        if (reg1 > 15 || reg2 < 0x0b) {
            Log.e(TAG, "no valid PLL combination for $freqHz Hz")
            return false
        }

        reg6 = reg6 or 0x20 // fix clock out

        // Fractional part for the delta-sigma modulator. This deliberately
        // uses the *unrounded* quotient, matching librtlsdr — using xdiv here
        // would go negative whenever the rounding stepped it up.
        var xin = ((fVco - quotient.toLong() * xtalDiv2) / 1000).toInt()
        xin = (xin shl 15) / (xtalDiv2 / 1000)
        if (xin >= 16384) xin += 32768
        val reg3 = (xin shr 8) and 0xff
        val reg4 = xin and 0xff

        // Bits 6-7 of reg 6 carry the channel bandwidth.
        reg6 = reg6 and 0x3f
        reg6 = reg6 or when (CHANNEL_BANDWIDTH_HZ) {
            6_000_000 -> 0x80
            7_000_000 -> 0x40
            else -> 0x00
        }
        reg5 = reg5 or 0x07 // modified for the Realtek demodulator

        val regs = intArrayOf(0, reg1, reg2, reg3, reg4, reg5, reg6)
        for (i in 1..6) {
            if (!writeReg(i, regs[i])) return false
        }

        val r11 = readReg(0x11)
        if (r11 < 0) return false
        if (!writeReg(0x11, if (multi == 64) r11 or 0x04 else r11 and 0xfb)) return false

        // VCO calibration: toggle, then read the resulting code back.
        if (!writeReg(0x0e, 0x80)) return false
        if (!writeReg(0x0e, 0x00)) return false
        if (!writeReg(0x0e, 0x00)) return false
        val calibration = readReg(0x0e)
        if (calibration < 0) return false

        // If the code railed, the other VCO band is the right one — switch and
        // re-calibrate.
        val code = calibration and 0x3f
        val needsReband = if (vcoSelect) code > 0x3c else code < 0x02
        if (needsReband) {
            reg6 = if (vcoSelect) reg6 and 0xf7 else reg6 or 0x08
            if (!writeReg(0x06, reg6)) return false
            if (!writeReg(0x0e, 0x80)) return false
            if (!writeReg(0x0e, 0x00)) return false
        }

        hasLock = true
        return true
    }

    // --------------------------------------------------------------- gain ---

    override fun setGain(manual: Boolean, gainTenthsDb: Int): Boolean {
        val r0d = readReg(0x0d)
        if (r0d < 0) return false
        // Bit 3 set = manual gain, clear = the tuner's own AGC.
        val mode = if (manual) r0d or 0x08 else r0d and 0xf7
        if (!writeReg(0x0d, mode)) return false

        // librtlsdr pins the IF gain and drives only the LNA.
        if (!writeReg(0x13, 0x0a)) return false

        return if (manual) setLnaGain(gainTenthsDb) else true
    }

    private fun setLnaGain(gainTenthsDb: Int): Boolean {
        val current = readReg(0x14)
        if (current < 0) return false

        var value = current and 0xe0
        val steps = LNA_GAINS.size / 2
        for (i in 0 until steps) {
            // First step at or above the request; the last entry is the cap.
            if (LNA_GAINS[i * 2] >= gainTenthsDb || i == steps - 1) {
                value = value or LNA_GAINS[i * 2 + 1]
                break
            }
        }
        return writeReg(0x14, value)
    }
}
