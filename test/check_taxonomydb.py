#!/usr/bin/env python3
"""Decide whether two taxonomyDB files differ only in TaxonNode's padding hole.

TaxonNode is {int id; int taxId; int parentTaxId; size_t rankIdx; size_t nameIdx},
so the compiler leaves four bytes unwritten at offset 12 to align rankIdx. serialize()
memcpy's the struct straight out, uninitialised hole and all. Two builds can therefore
write different bytes there while meaning exactly the same taxonomy.
"""

import struct
import sys

NODE_SIZE = 32
HOLE = range(12, 16)


def header(buf):
    """(node block offset, node count) for both header shapes serialize() can write."""
    for internal in (False, True):
        p = 4 + (8 if internal else 0)
        max_nodes = struct.unpack_from("<Q", buf, p)[0]
        p += 8 + 4
        if 0 < max_nodes < 10_000_000 and p + max_nodes * NODE_SIZE <= len(buf):
            yield p, max_nodes


def main():
    a, b = (open(p, "rb").read() for p in sys.argv[1:3])
    if len(a) != len(b):
        print("sizes differ: %d vs %d" % (len(a), len(b)))
        return 1
    diffs = [i for i in range(len(a)) if a[i] != b[i]]
    if not diffs:
        print("identical")
        return 0

    for start, n in header(a):
        end = start + n * NODE_SIZE
        if all(start <= i < end and (i - start) % NODE_SIZE in HOLE for i in diffs):
            nodes = sorted({(i - start) // NODE_SIZE for i in diffs})
            print("%d byte(s) differ, all of them TaxonNode padding "
                  "(nodes %s of %d, block at %d)"
                  % (len(diffs), ",".join(map(str, nodes)), n, start))
            return 0

    print("%d byte(s) differ and they are NOT all padding: %s%s"
          % (len(diffs), diffs[:16], " ..." if len(diffs) > 16 else ""))
    return 1


if __name__ == "__main__":
    sys.exit(main())
