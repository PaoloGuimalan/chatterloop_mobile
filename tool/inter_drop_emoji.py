"""Removes emoji-capable code points from Inter's cmap, so the system's colour
emoji font draws them (as before Inter was bundled) instead of Inter's
monochrome text glyphs - which take the TEXT colour, e.g. a white ❤ on a dark
screen.

Only the cmap changes: glyphs, metrics, kerning and features are untouched.
The fonts are OFL-licensed with no Reserved Font Name, so a modified copy may
keep the name.

Usage (from chatterloop_app/), rewrites in place:
  python tool/inter_drop_emoji.py assets/fonts/Inter-*.ttf
Keep DROP in step with _emojiInInter in test/fonts_test.dart.
"""
import math
import struct
import sys

# Code points with the Unicode "Emoji" property that Inter maps to its own
# (monochrome) glyph. ©, ® and ™ stay: the app sets them as text.
DROP = [
    0x203C, 0x2049,
    0x2194, 0x2195, 0x2196, 0x2197, 0x2198, 0x2199, 0x21A9, 0x21AA,
    0x23CF, 0x24C2, 0x25AA, 0x25B6, 0x25C0,
    0x2600, 0x2665, 0x26A0, 0x2764,
    0x2B06, 0x2B1C,
]


def read_tables(data):
    num = struct.unpack('>H', data[4:6])[0]
    recs = []
    for i in range(num):
        tag, checksum, offset, length = struct.unpack(
            '>4sIII', data[12 + 16 * i:28 + 16 * i])
        recs.append([tag, checksum, offset, length])
    return recs


def full_mapping(cmap):
    """Code point -> glyph, from the format 12 subtable (complete)."""
    _, count = struct.unpack('>HH', cmap[:4])
    for i in range(count):
        pid, eid, sub = struct.unpack('>HHI', cmap[4 + 8 * i:12 + 8 * i])
        if struct.unpack('>H', cmap[sub:sub + 2])[0] != 12:
            continue
        n = struct.unpack('>I', cmap[sub + 12:sub + 16])[0]
        mapping = {}
        for k in range(n):
            s, e, g = struct.unpack(
                '>III', cmap[sub + 16 + 12 * k:sub + 28 + 12 * k])
            for c in range(s, e + 1):
                mapping[c] = g + (c - s)
        return mapping
    raise SystemExit('no format 12 cmap')


def runs(codes, mapping, contiguous_glyphs):
    """Consecutive code points (and, if asked, consecutive glyphs)."""
    out = []
    for c in codes:
        if out and c == out[-1][-1] + 1 and (
                not contiguous_glyphs or mapping[c] == mapping[out[-1][-1]] + 1):
            out[-1].append(c)
        else:
            out.append([c])
    return out


def format4(mapping):
    codes = sorted(c for c in mapping if c < 0xFFFF)
    segs = runs(codes, mapping, contiguous_glyphs=False)
    starts, ends, deltas, offsets, glyph_array = [], [], [], [], []
    for seg in segs:
        glyphs = [mapping[c] for c in seg]
        starts.append(seg[0])
        ends.append(seg[-1])
        if all(glyphs[i] == glyphs[0] + i for i in range(len(glyphs))):
            deltas.append((glyphs[0] - seg[0]) & 0xFFFF)
            offsets.append(None)
        else:
            deltas.append(0)
            offsets.append(len(glyph_array))
            glyph_array.extend(glyphs)
    # The required closing segment.
    starts.append(0xFFFF)
    ends.append(0xFFFF)
    deltas.append(1)
    offsets.append(None)

    seg_count = len(starts)
    range_offsets = []
    for i, off in enumerate(offsets):
        range_offsets.append(0 if off is None else 2 * (seg_count - i) + 2 * off)
    search_range = 2 * (2 ** int(math.floor(math.log2(seg_count))))
    entry_selector = int(math.log2(search_range // 2))
    range_shift = 2 * seg_count - search_range
    body = struct.pack('>%dH' % seg_count, *ends) + b'\0\0' + \
        struct.pack('>%dH' % seg_count, *starts) + \
        struct.pack('>%dH' % seg_count, *deltas) + \
        struct.pack('>%dH' % seg_count, *range_offsets) + \
        struct.pack('>%dH' % len(glyph_array), *glyph_array)
    length = 14 + len(body)
    assert length < 0x10000, length
    return struct.pack('>7H', 4, length, 0, 2 * seg_count, search_range,
                       entry_selector, range_shift) + body


def format12(mapping):
    groups = runs(sorted(mapping), mapping, contiguous_glyphs=True)
    body = b''.join(struct.pack('>III', g[0], g[-1], mapping[g[0]])
                    for g in groups)
    return struct.pack('>HHIII', 12, 0, 16 + len(body), 0, len(groups)) + body


def build_cmap(mapping):
    f4 = format4(mapping)
    f12 = format12(mapping)
    header = 4 + 8 * 4
    f4_at, f12_at = header, header + len(f4)
    records = [(0, 3, f4_at), (0, 4, f12_at), (3, 1, f4_at), (3, 10, f12_at)]
    out = struct.pack('>HH', 0, len(records))
    for pid, eid, off in records:
        out += struct.pack('>HHI', pid, eid, off)
    return out + f4 + f12


def checksum(data):
    data += b'\0' * (-len(data) % 4)
    return sum(struct.unpack('>%dI' % (len(data) // 4), data)) & 0xFFFFFFFF


def rewrite(path):
    data = open(path, 'rb').read()
    recs = read_tables(data)
    blobs = {rec[0]: data[rec[2]:rec[2] + rec[3]] for rec in recs}

    mapping = full_mapping(blobs[b'cmap'])
    removed = [c for c in DROP if c in mapping]
    for c in removed:
        del mapping[c]
    blobs[b'cmap'] = build_cmap(mapping)

    head = bytearray(blobs[b'head'])
    head[8:12] = b'\0\0\0\0'  # checkSumAdjustment, recomputed below
    blobs[b'head'] = bytes(head)

    num = len(recs)
    offset = 12 + 16 * num
    layout = []
    # Same physical order as the original file.
    for rec in sorted(recs, key=lambda r: r[2]):
        blob = blobs[rec[0]]
        layout.append((rec[0], offset, blob))
        offset += len(blob) + (-len(blob) % 4)

    directory = {tag: (off, blob) for tag, off, blob in layout}
    out = bytearray(data[:12])
    for rec in recs:  # directory stays sorted by tag, as it was
        off, blob = directory[rec[0]]
        out += struct.pack('>4sIII', rec[0], checksum(blob), off, len(blob))
    for tag, off, blob in layout:
        assert len(out) == off
        out += blob + b'\0' * (-len(blob) % 4)

    adjustment = (0xB1B0AFBA - checksum(bytes(out))) & 0xFFFFFFFF
    head_off = directory[b'head'][0]
    out[head_off + 8:head_off + 12] = struct.pack('>I', adjustment)
    open(path, 'wb').write(bytes(out))
    return removed


if __name__ == '__main__':
    for path in sys.argv[1:]:
        removed = rewrite(path)
        print(path, 'dropped', ' '.join('U+%04X' % c for c in removed))
