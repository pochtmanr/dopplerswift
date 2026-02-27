#!/usr/bin/env python3
"""Strip geoip.dat to only include specified countries."""

import sys

from google.protobuf.internal.decoder import _DecodeVarint
from google.protobuf.internal.encoder import _EncodeVarint

KEEP_COUNTRIES = {
    "DE", "GB", "FR", "NL", "RU", "US", "TR", "IT", "ES", "PL",
    "UA", "KZ", "AE", "IL", "CN", "BR", "JP", "KR", "IN", "AU", "CA",
}


def read_varint(data, pos):
    result, new_pos = _DecodeVarint(data, pos)
    return result, new_pos


def write_varint(value):
    pieces = []
    _EncodeVarint(pieces.append, value)
    return b''.join(pieces)


def parse_geoip_entries(data):
    """Parse GeoIPList: repeated GeoIP (field 1, length-delimited)."""
    entries = []
    pos = 0
    while pos < len(data):
        tag, pos = read_varint(data, pos)
        field_number = tag >> 3
        wire_type = tag & 0x7

        if wire_type == 2:  # length-delimited
            length, pos = read_varint(data, pos)
            entry_data = data[pos:pos + length]
            pos += length

            if field_number == 1:  # GeoIP entry
                country_code = parse_country_code(entry_data)
                entries.append((country_code, entry_data))
        else:
            break

    return entries


def parse_country_code(entry_data):
    """Extract country_code (field 1) from a GeoIP message."""
    pos = 0
    while pos < len(entry_data):
        tag, pos = read_varint(entry_data, pos)
        field_number = tag >> 3
        wire_type = tag & 0x7

        if wire_type == 2:  # length-delimited
            length, pos = read_varint(entry_data, pos)
            if field_number == 1:
                return entry_data[pos:pos + length].decode('utf-8')
            pos += length
        elif wire_type == 0:  # varint
            _, pos = read_varint(entry_data, pos)
        else:
            break
    return ""


def rebuild_geoip_list(entries):
    """Re-encode a GeoIPList from filtered entries."""
    result = b''
    for country_code, entry_data in entries:
        tag = write_varint((1 << 3) | 2)
        length = write_varint(len(entry_data))
        result += tag + length + entry_data
    return result


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.dat> <output.dat>")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    with open(input_path, 'rb') as f:
        data = f.read()

    print(f"Input: {len(data)} bytes")

    entries = parse_geoip_entries(data)
    print(f"Total entries: {len(entries)}")
    for cc, _ in entries:
        if cc.upper() in KEEP_COUNTRIES:
            print(f"  KEEP: {cc}")

    filtered = [(cc, d) for cc, d in entries if cc.upper() in KEEP_COUNTRIES]
    print(f"Filtered entries: {len(filtered)}")

    output = rebuild_geoip_list(filtered)

    with open(output_path, 'wb') as f:
        f.write(output)

    print(f"Output: {len(output)} bytes ({len(output) / len(data) * 100:.1f}% of original)")


if __name__ == '__main__':
    main()
