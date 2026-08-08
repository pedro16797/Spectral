package com.jundroo.spectral.usb

/**
 * A tuner chip hanging off the RTL2832U's I2C bus.
 *
 * The demodulator opens and closes the I2C repeater around every call, so
 * implementations can talk to their chip directly via [Rtl2832u.i2cWrite] /
 * [Rtl2832u.i2cRead] without managing the repeater themselves.
 */
interface RtlTunerDriver {
    /**
     * The tuner's reference crystal in Hz, with any PPM correction already
     * applied. Not always the same as the RTL2832U's own crystal — the R828D
     * uses 16 MHz where the demodulator uses 28.8 MHz.
     */
    var xtalHz: Int

    /** Whether the last tune produced a locked PLL. */
    val hasLock: Boolean

    /** Brings the tuner up. Returns null on success, or the reason it failed. */
    fun init(): String?

    /** Tunes to [freqHz]. */
    fun setFreq(freqHz: Int): Boolean

    /**
     * [manual] false hands gain control to the tuner's own AGC; true applies
     * [gainTenthsDb] as a fixed gain.
     */
    fun setGain(manual: Boolean, gainTenthsDb: Int): Boolean
}
