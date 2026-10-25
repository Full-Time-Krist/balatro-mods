"""Read and write the Lua table files RuFill uses (rufill_dump.lua, ru.lua).

Only the subset those files contain: `return { ... }` with string/number keys and
string/number/boolean/table values. Lua arrays come back as dicts with int keys,
so paths like text|1 map straight onto them.
"""
import re

_TOKEN = re.compile(r"""
    \s+ | --[^\n]* |
    (?P<str>"(?:[^"\\]|\\.|\\\n)*") |
    (?P<num>-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?) |
    (?P<name>[A-Za-z_][A-Za-z0-9_]*) |
    (?P<sym>[{}\[\]=,;])
""", re.X | re.S)

_ESC = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
        "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def _unquote(s):
    body, out, i = s[1:-1], [], 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        n = body[i + 1]
        if n.isdigit():
            j = i + 1
            while j < len(body) and j < i + 4 and body[j].isdigit():
                j += 1
            out.append(chr(int(body[i + 1:j])))
            i = j
        else:
            out.append(_ESC.get(n, n))
            i += 2
    # Lua strings are bytes; the files are UTF-8, so \ddd escapes are UTF-8 bytes too.
    text = "".join(out)
    try:
        return text.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return text


def _tokens(src):
    pos = 0
    for m in _TOKEN.finditer(src):
        if m.start() != pos:
            raise ValueError(f"unexpected text at {pos}: {src[pos:pos + 30]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind:
            yield kind, m.group(kind)
    if pos != len(src):
        raise ValueError(f"unexpected text at {pos}: {src[pos:pos + 30]!r}")


def loads(src):
    src = src.lstrip("\ufeff")
    toks = list(_tokens(src))
    i = 0

    def peek():
        return toks[i] if i < len(toks) else (None, None)

    def take(kind=None, val=None):
        nonlocal i
        t = toks[i]
        if (kind and t[0] != kind) or (val and t[1] != val):
            raise ValueError(f"expected {val or kind}, got {t[1]!r}")
        i += 1
        return t

    def value():
        kind, v = peek()
        if kind == "str":
            take()
            return _unquote(v)
        if kind == "num":
            take()
            return float(v) if any(c in v for c in ".eE") else int(v)
        if kind == "name" and v in ("true", "false", "nil"):
            take()
            return {"true": True, "false": False, "nil": None}[v]
        if v == "{":
            return table()
        raise ValueError(f"unexpected {v!r}")

    def table():
        take("sym", "{")
        t, n = {}, 1
        while peek()[1] != "}":
            kind, v = peek()
            if v == "[":
                take()
                key = value()
                take("sym", "]")
                take("sym", "=")
                t[key] = value()
            elif kind == "name" and i + 1 < len(toks) and toks[i + 1][1] == "=":
                take()
                take("sym", "=")
                t[v] = value()
            else:
                t[n] = value()
                n += 1
            if peek()[1] in (",", ";"):
                take()
        take("sym", "}")
        return t

    if peek() == ("name", "return"):
        take()
    return value()


def _quote(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r").replace("\0", "\\000")
    return '"' + s + '"'


def _sort_key(k):
    return (0, k, "") if isinstance(k, (int, float)) else (1, 0, k.encode("utf-8"))


_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def dumps(v, indent=""):
    """Same layout as RuFill's tools/import.lua serializer."""
    if isinstance(v, str):
        return _quote(v)
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    pad = indent + "\t"
    out = ["{\n"]
    for k in sorted(v, key=_sort_key):
        if isinstance(k, (int, float)):
            key = f"[{k}] = "
        else:
            key = (k if _IDENT.match(k) else "[" + _quote(k) + "]") + " = "
        out.append(pad + key + dumps(v[k], pad) + ",\n")
    out.append(indent + "}")
    return "".join(out)


def load_file(path):
    with open(path, encoding="utf-8") as f:
        return loads(f.read())


def save_file(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("return " + dumps(data) + "\n")
