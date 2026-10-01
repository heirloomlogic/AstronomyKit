#!/usr/bin/env python3
"""Rewrite the engine sources so every double becomes __float128.

Every floating literal gets a Q suffix, so the reference evaluates the
decimal constants in the source rather than their binary64 roundings.
String literals are left alone.
"""
import re
import sys
from pathlib import Path

MATH = r"\b(sin|cos|tan|asin|acos|atan|atan2|sqrt|hypot|fmod|floor|ceil|fabs|fmax|fmin|exp|log|log10|pow|cbrt)\s*\("
CLASSIFY = {"isfinite": "finiteq", "isnan": "isnanq", "isinf": "isinfq"}
HEX_FLOAT = r"0[xX][0-9a-fA-F]*\.?[0-9a-fA-F]*[pP][-+]?\d+"
DEC_FLOAT = r"(?<![\w.])(?:\d+\.\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?|\d+[eE][-+]?\d+)(?![\w.])"
STRING = r'"(?:\\.|[^"\\])*"'
# The thread-local caches key on the 8 bytes of a binary64; mix all 16 bytes of the wider type.
CACHE_KEY = r"memcpy\(&(\w+), &t, sizeof\(\1\)\);"
CACHE_KEY_MIX = r"{ uint64_t halves[2]; memcpy(halves, &t, sizeof(halves)); \1 = halves[0] ^ (halves[1] * 0x9E3779B97F4A7C15ULL); }"


def transform_code(text):
    text = re.sub(r"\bdouble\b", "__float128", text)
    text = re.sub(MATH, lambda m: m.group(1) + "q(", text)
    text = re.sub(r"\b(isfinite|isnan|isinf)\s*\(", lambda m: CLASSIFY[m.group(1)] + "(", text)
    text = re.sub(HEX_FLOAT, lambda m: m.group(0) + "Q", text)
    text = re.sub(DEC_FLOAT, lambda m: m.group(0) + "Q", text)
    return text


def transform(text):
    out = []
    pos = 0
    for m in re.finditer(STRING, text):
        out.append(transform_code(text[pos:m.start()]))
        out.append(m.group(0))
        pos = m.end()
    out.append(transform_code(text[pos:]))
    return "".join(out)


if __name__ == "__main__":
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    body = transform(src.read_text())
    if src.name == "astronomy.c":
        body, count = re.subn(CACHE_KEY, CACHE_KEY_MIX, body)
        if count != 3:
            raise SystemExit(f"expected 3 cache key copies in astronomy.c, rewrote {count}; update quad_transform.py")
    if src.suffix == ".c" or src.name == "astronomy.h":
        body = "#include <quadmath.h>\n" + body
    dst.write_text(body)
