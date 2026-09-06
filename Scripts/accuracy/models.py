"""Build isolated diagnostic libraries; model selection never enters production API."""
import hashlib
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASELINE = "8e88bb462364265a66cf78c10a6e5932b17fad0b"


def region(source, first, last):
    start = source.index(first)
    return source[start:source.index(last, start)]


def build(directory):
    subprocess.run([sys.executable, str(ROOT / "Scripts/generate-models.py"), "--check"], check=True)
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    original = subprocess.check_output(
        ["git", "show", f"{BASELINE}:Sources/CLibAstronomy/astronomy.c"], cwd=ROOT, text=True)
    old_vsop = region(original, "static const vsop_term_t vsop_lon_Mercury_0[]", "/** @cond DOXYGEN_SKIP */\n#define VSOPFORMULA")
    old_nutation = region(original, "static void iau2000b(", "static double mean_obliq(")
    new_nutation = (ROOT / "Scripts/accuracy/nutation.c.inc").read_text()
    full_vsop = original.replace(old_vsop, '#include "vsop87b_full.h"\n\n')
    variants = {
        "baseline": original,
        "vsop": full_vsop,
        "nutation": original.replace(old_nutation, new_nutation),
        "full": full_vsop.replace(old_nutation, new_nutation),
    }
    result = {}
    croot = ROOT / "Sources/CLibAstronomy"
    for name, source in variants.items():
        print(f"Building diagnostic model: {name}", flush=True)
        path = directory / f"{name}.c"
        path.write_text(source)
        library = directory / (name + (".dylib" if sys.platform == "darwin" else ".so"))
        subprocess.run(["clang", "-O2", "-dynamiclib" if sys.platform == "darwin" else "-shared",
                        "-fPIC", "-pthread", "-I", str(croot / "include"), "-I", str(croot),
                        "-I", str(ROOT / "Sources/CLibAstronomy/generated"),
                        str(path), str(ROOT / "Scripts/accuracy/sample.c"),
                        *map(str, sorted((croot / "detmath").glob("*.c"))), "-lm", "-o", str(library)], check=True)
        result[name] = {"path": str(library), "sourceSHA256": hashlib.sha256(source.encode()).hexdigest(),
                        "binarySHA256": hashlib.sha256(library.read_bytes()).hexdigest()}
    return result
