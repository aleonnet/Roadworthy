"""Compare a hook's stdout against a golden envelope, key for key.

The golden carries the fixed values literally; two placeholders stand for what varies:
  {{reason}}  a non-empty string beginning with "Roadworthy"
  {{text}}    a non-empty string
Keys beginning with "_" are documentation of the golden itself and are ignored.
Exit 0 when the shape matches; exit 1 with the first divergence on stderr.
"""
import json, sys

def clean(d):
    return {k: v for k, v in d.items() if not k.startswith("_")}

def shape(want, got, path=""):
    want = clean(want)
    if not isinstance(got, dict):
        return f"{path or '/'}: expected an object, got {type(got).__name__}"
    if set(want) != set(got):
        return (f"{path or '/'}: keys differ — expected {sorted(want)}, got {sorted(got)}")
    for k, v in want.items():
        here = f"{path}/{k}"
        if isinstance(v, dict):
            m = shape(v, got[k], here)
            if m:
                return m
        elif v == "{{reason}}":
            if not isinstance(got[k], str) or not got[k].startswith("Roadworthy"):
                return f"{here}: expected a reason starting with 'Roadworthy', got {got[k]!r}"
        elif v == "{{text}}":
            if not isinstance(got[k], str) or not got[k]:
                return f"{here}: expected a non-empty string, got {got[k]!r}"
        elif v != got[k]:
            return f"{here}: expected {v!r}, got {got[k]!r}"
    return ""

golden = json.load(open(sys.argv[1], encoding="utf-8"))
raw = sys.stdin.read()
try:
    got = json.loads(raw)
except Exception as e:
    sys.stderr.write(f"not JSON at all: {e}\n"); sys.exit(1)
m = shape(golden, got)
if m:
    sys.stderr.write(m + "\n"); sys.exit(1)
