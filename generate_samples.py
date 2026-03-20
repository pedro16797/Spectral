import struct
import math

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
