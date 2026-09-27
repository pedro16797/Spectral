"""Regenerates the bundled demo sample files under resources/samples/."""
import math
import os
import struct

# Paths are repo-relative; run from anywhere.
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
os.makedirs('resources/samples/audio', exist_ok=True)
os.makedirs('resources/samples/rf', exist_ok=True)

def write_wav(filename, samples, sample_rate):
    with open(filename, 'wb') as f:
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + len(samples) * 2))
        f.write(b'WAVEfmt ')
        f.write(struct.pack('<I', 16))
        f.write(struct.pack('<HHIIHH', 1, 1, sample_rate, sample_rate * 2, 2, 16))
        f.write(b'data')
        f.write(struct.pack('<I', len(samples) * 2))
        for s in samples:
            f.write(struct.pack('<h', int(s * 32767)))

# Audio: 440Hz Sine Wave + 880Hz Harmonic
sr = 44100
duration = 1.0
audio_samples = []
for i in range(int(sr * duration)):
    t = i / sr
    s = 0.5 * math.sin(2 * math.pi * 440 * t) + 0.25 * math.sin(2 * math.pi * 880 * t)
    audio_samples.append(s)
write_wav('resources/samples/audio/sine_440_880.wav', audio_samples, sr)

# Audio: a chirp sweeping 500 Hz -> 15 kHz and back, over a steady 2 kHz
# tone, so the waterfall shows a moving signal crossing a fixed one.
#
# The file loops seamlessly: its length is a whole number of the playback
# source's 1024-sample reads (a partial read at the end is skipped), and the
# sweep is scaled so each loop spans a whole number of cycles, which keeps the
# phase continuous across the wrap. Either seam would draw a click as a
# horizontal line across the waterfall once per loop.
chirp_len = 1024 * 345  # ~8 s at 44.1 kHz
f_lo, f_hi = 500.0, 15000.0
sweep = []
for i in range(chirp_len):
    u = i / chirp_len  # Triangle: up for the first half, down for the second.
    tri = 2 * u if u < 0.5 else 2 * (1 - u)
    sweep.append(f_lo + (f_hi - f_lo) * tri)
cycles = sum(sweep) / sr
sweep = [f * round(cycles) / cycles for f in sweep]
tone = round(2000 * chirp_len / sr) * sr / chirp_len  # ~2 kHz, whole cycles.
chirp_samples = []
phase = 0.0
for i in range(chirp_len):
    chirp_samples.append(0.6 * math.sin(phase) +
                         0.2 * math.sin(2 * math.pi * tone * i / sr))
    phase += 2 * math.pi * sweep[i] / sr
write_wav('resources/samples/audio/chirp_sweep.wav', chirp_samples, sr)

# SDR: IQ Data (Complex)
# We'll save it as a .wav file but treat it as IQ (I in Left, Q in Right channel)
# For simplicity, let's just create a raw binary file for now
def write_iq(filename, samples):
    with open(filename, 'wb') as f:
        for s in samples:
            # s is a complex number
            # Interleaved I and Q as float32
            f.write(struct.pack('<ff', s.real, s.imag))

# Multiple FM signals (centered at 0, +250k, -100k)
sr_rf = 1000000 # 1MHz bandwidth
iq_samples = []
for i in range(sr_rf):
    t = i / sr_rf
    # Signal 1 at DC (0 Hz)
    s1 = 0.5 * math.e**(1j * 2 * math.pi * 0 * t)
    # Signal 2 at +250 kHz
    s2 = 0.3 * math.e**(1j * 2 * math.pi * 250000 * t)
    # Signal 3 at -100 kHz
    s3 = 0.4 * math.e**(1j * 2 * math.pi * -100000 * t)
    iq_samples.append(s1 + s2 + s3)

write_iq('resources/samples/rf/fm_multi_signals.iq', iq_samples)
print("Samples generated.")
