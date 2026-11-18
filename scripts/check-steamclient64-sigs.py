#!/usr/bin/env python3
"""Check that a 64-bit steamclient.so contains exactly one match for each
protobuf helper signature cloud_redirect.so resolves at startup
(see CloudHooks::ResolveProtobufHelpers in src/platform/linux/cloud_hooks.cpp).
Reads the file only. Exit 0 = all unique, 1 = missing/ambiguous, 2 = bad input."""
import sys

SERIALIZE = bytes([
    0x48,0x83,0xEC,0x18, 0x48,0x8B,0x07, 0x48,0x89,0x74,0x24,0x08,
    0x48,0x89,0x3C,0x24, 0xFF,0x50,0x50, 0x48,0x8B,0x74,0x24,0x08,
    0x48,0x8B,0x3C,0x24, 0x48,0x83,0xC4,0x18, 0x89,0xC2,0xE9])
PARSE = bytes([0x41,0x55,0x41,0x54,0x55,0x48,0x63,0xEA,0x48,0x85,0xED,0x79,0x1F])
PARSE_TAIL_OFF = 0x2C
PARSE_TAIL = bytes([
    0x48,0x8B,0x07,0x49,0x89,0xFC,0x49,0x89,0xF5,0xFF,0x50,0x28,
    0x4C,0x89,0xE2,0x4C,0x89,0xEF,0x48,0x89,0xEE,0xB9,0x01,0,0,0,
    0x5D,0x41,0x5C,0x41,0x5D,0xE9])

def find_all(data, pat, tail_off=0, tail=b""):
    hits, i = [], data.find(pat)
    while i != -1:
        if not tail or data[i + tail_off:i + tail_off + len(tail)] == tail:
            hits.append(i)
        i = data.find(pat, i + 1)
    return hits

def main():
    if len(sys.argv) != 2:
        print(__doc__); return 2
    data = open(sys.argv[1], "rb").read()
    if data[:5] != b"\x7fELF\x02":
        print("not a 64-bit ELF file"); return 2
    ok = True
    for name, hits in (("SerializeToArray", find_all(data, SERIALIZE)),
                       ("ParseFromArray", find_all(data, PARSE, PARSE_TAIL_OFF, PARSE_TAIL))):
        state = "OK" if len(hits) == 1 else ("MISSING" if not hits else f"AMBIGUOUS ({len(hits)})")
        print(f"{name}: {state}" + (f" at file offset 0x{hits[0]:x}" if len(hits) == 1 else ""))
        ok &= len(hits) == 1
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
