package com.example.spectral.usb

/**
 * USB vendor/product IDs of RTL2832U-based dongles.
 *
 * Keep in sync with `res/xml/device_filter.xml` (which expresses the same list
 * in decimal, for the USB_DEVICE_ATTACHED filter) and with `RtlUsbIds` in
 * `lib/src/rf/rtl2832u.dart`.
 */
object RtlUsbIds {
    const val VENDOR_REALTEK = 0x0bda

    /** (vendorId, productId) pairs known to contain an RTL2832U. */
    val KNOWN_DEVICES: List<Pair<Int, Int>> = listOf(
        0x0bda to 0x2831, // RTL2831U
        0x0bda to 0x2832, // RTL2832U
        0x0bda to 0x2834, // RTL2834
        0x0bda to 0x2837, // RTL2837
        0x0bda to 0x2838, // RTL2838 (RTL-SDR Blog v3 and most "RTL-SDR" dongles)
        0x0ccd to 0x00a9, // Terratec Cinergy T Stick Black
        0x0ccd to 0x00b3, // Terratec NOXON DAB/DAB+
        0x1d19 to 0x1101, // Dexatek DK DVB-T
        0x1b80 to 0xd3a4, // Twintech UT-40
        0x1f4d to 0xb803, // GTek T803
    )

    fun isKnownDongle(vendorId: Int, productId: Int): Boolean =
        KNOWN_DEVICES.contains(vendorId to productId)
}
