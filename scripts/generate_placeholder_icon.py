import zlib
import struct

def make_png(width, height, color):
    # PNG header
    png_header = b'\x89PNG\r\n\x1a\n'

    # IHDR chunk
    # Width: 4 bytes, Height: 4 bytes, Bit depth: 1 byte (8), Color type: 1 byte (2=RGB),
    # Compression: 1 byte (0), Filter: 1 byte (0), Interlace: 1 byte (0)
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    ihdr_chunk = make_chunk(b'IHDR', ihdr_data)

    # IDAT chunk
    # Each row starts with a filter byte (0 for none)
    row_size = width * 3
    row_data = bytes([0] + [c for _ in range(width) for c in color])
    all_rows_data = row_data * height
    idat_data = zlib.compress(all_rows_data)
    idat_chunk = make_chunk(b'IDAT', idat_data)

    # IEND chunk
    iend_chunk = make_chunk(b'IEND', b'')

    return png_header + ihdr_chunk + idat_chunk + iend_chunk

def make_chunk(type, data):
    length = struct.pack('>I', len(data))
    crc = struct.pack('>I', zlib.crc32(type + data) & 0xffffffff)
    return length + type + data + crc

if __name__ == "__main__":
    # Spectral Blue: #2196F3 -> (33, 150, 243)
    icon_data = make_png(1024, 1024, (33, 150, 243))
    with open("resources/icon.png", "wb") as f:
        f.write(icon_data)
    print("Generated 1024x1024 placeholder icon at resources/icon.png")
