"""Add a dylib load command only inside verified empty Mach-O header padding."""
import struct


def inject(binary: bytes, name: str) -> bytes:
    data = bytearray(binary)
    if data[:4] != bytes.fromhex('cafebabe'):
        raise ValueError('Expected universal Mach-O')
    raw = name.encode() + b'\0'
    size = (24 + len(raw) + 7) & ~7
    load = struct.pack('<IIIIII', 0xc, size, 24, 0, 0, 0) + raw
    load = load.ljust(size, b'\0')
    for i in range(struct.unpack_from('>I', data, 4)[0]):
        cpu, _, base, image_size, _ = struct.unpack_from('>IIIII', data, 8 + 20 * i)
        if cpu not in (0x1000007, 0x100000c):
            raise ValueError('Unexpected architecture')
        count, total = struct.unpack_from('<II', data, base + 16)
        cursor = base + 32
        first = image_size
        for _ in range(count):
            command, length = struct.unpack_from('<II', data, cursor)
            if length < 8:
                raise ValueError('Invalid command length')
            if command == 0x19:
                section_count = struct.unpack_from('<I', data, cursor + 64)[0]
                for j in range(section_count):
                    offset = struct.unpack_from('<I', data, cursor + 72 + 80 * j + 48)[0]
                    if offset:
                        first = min(first, offset)
            cursor += length
        if cursor != base + 32 + total:
            raise ValueError('Command size mismatch')
        if cursor + size > base + first or any(data[cursor:cursor + size]):
            raise ValueError('Insufficient empty header padding')
        data[cursor:cursor + size] = load
        struct.pack_into('<II', data, base + 16, count + 1, total + size)
    return bytes(data)
