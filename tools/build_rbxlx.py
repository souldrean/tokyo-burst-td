"""
build_rbxlx.py — "mini Rojo" do Tokyo Burst TD.

O que faz: le o default.project.json, junta todos os arquivos .luau e o mapa
(.model.json) e gera UM arquivo build/TokyoBurstTD.rbxlx. Voce abre esse arquivo
no Roblox Studio (duplo clique) e o jogo inteiro aparece pronto.

Por que existe: assim voce nao precisa instalar Rojo agora. Quando quiser o fluxo
profissional, o mesmo projeto funciona com `rojo serve` / `rojo build`.

Uso (na raiz do projeto):
    python3 -I tools/build_rbxlx.py
"""

from __future__ import annotations

import base64
import json
import re
import struct
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "TokyoBurstTD.rbxlx"

# Filhos de servicos que tem classe propria (o resto vira Folder).
SPECIAL_CLASSES = {
    "StarterPlayerScripts": "StarterPlayerScripts",
    "StarterCharacterScripts": "StarterCharacterScripts",
}

# Enum.Material -> valor numerico usado no arquivo.
MATERIALS = {
    "Plastic": 256,
    "SmoothPlastic": 272,
    "Neon": 288,
    "Wood": 512,
    "Slate": 800,
    "Concrete": 816,
    "Brick": 848,
    "Metal": 1088,
    "Grass": 1280,
    "Sand": 1296,
    "Asphalt": 1376,
    "Glass": 1568,
}

BOOL_PROPS = {"Anchored", "CanCollide", "CanQuery", "CanTouch", "Neutral", "Locked", "CastShadow"}
FLOAT_PROPS = {"Transparency", "Reflectance"}
INT_PROPS = {"Duration"}
STRING_PROPS = {"Name"}


class Inst:
    def __init__(self, cls: str, name: str):
        self.cls = cls
        self.name = name
        self.props: dict[str, tuple[str, object]] = {}  # name -> (kind, value)
        self.attrs: dict[str, object] = {}
        self.children: list[Inst] = []


# ---------------------------------------------------------------- leitura

def script_from_file(path: Path, name: str | None = None) -> Inst:
    fname = path.name
    for suffix, cls in ((".server.luau", "Script"), (".server.lua", "Script"),
                        (".client.luau", "LocalScript"), (".client.lua", "LocalScript"),
                        (".luau", "ModuleScript"), (".lua", "ModuleScript")):
        if fname.endswith(suffix):
            inst = Inst(cls, name or fname[: -len(suffix)])
            inst.props["Source"] = ("source", path.read_text(encoding="utf-8"))
            return inst
    raise ValueError(f"nao sei converter {path}")


def from_path(path: Path, name: str) -> Inst:
    if path.is_file():
        if path.name.endswith(".model.json"):
            return model_from_json(json.loads(path.read_text(encoding="utf-8")), name)
        return script_from_file(path, name)
    if not path.is_dir():
        raise FileNotFoundError(f"$path nao existe: {path}")

    # Pasta com init.* vira o proprio script; o resto vira filho dele.
    inst: Inst | None = None
    for init in ("init.server.luau", "init.client.luau", "init.luau",
                 "init.server.lua", "init.client.lua", "init.lua"):
        if (path / init).is_file():
            inst = script_from_file(path / init, name)
            break
    if inst is None:
        inst = Inst("Folder", name)

    for child in sorted(path.iterdir()):
        if child.name.startswith(".") or child.name.startswith("init."):
            continue
        if child.is_dir():
            inst.children.append(from_path(child, child.name))
        elif child.name.endswith(".model.json"):
            inst.children.append(from_path(child, child.name[: -len(".model.json")]))
        elif child.suffix in (".luau", ".lua"):
            inst.children.append(script_from_file(child))
    return inst


def model_from_json(data: dict, name: str | None = None) -> Inst:
    inst = Inst(data.get("ClassName", "Folder"), name or data.get("Name", "Instance"))
    props = dict(data.get("Properties") or {})
    # Formato do Rojo: Properties.Attributes = {"Attributes": {nome: {Tipo: valor}}}
    attrs = dict(data.get("Attributes") or {})
    rojo_attrs = props.pop("Attributes", None)
    if isinstance(rojo_attrs, dict):
        for key, typed in (rojo_attrs.get("Attributes") or {}).items():
            attrs[key] = next(iter(typed.values())) if isinstance(typed, dict) else typed
    for key, value in props.items():
        inst.props[key] = classify(key, value)
    for key, value in attrs.items():
        if not isinstance(value, (bool, int, float, str)):
            raise ValueError(f"atributo {key} tem tipo nao suportado: {value!r}")
        inst.attrs[key] = value
    for child in data.get("Children") or []:
        inst.children.append(model_from_json(child))
    return inst


def classify(key: str, value: object) -> tuple[str, object]:
    if key == "Size":
        return ("vector3", value)
    if key == "CFrame":
        # Aceita o formato explicito do Rojo ({"CFrame": {...}}) e o antigo.
        if isinstance(value, dict) and "CFrame" in value:
            value = value["CFrame"]
        return ("cframe", value)
    if key == "Color":
        return ("color", value)
    if key == "Material":
        if value not in MATERIALS:
            raise ValueError(f"Material desconhecido: {value}")
        return ("token", MATERIALS[value])
    if key in BOOL_PROPS:
        return ("bool", bool(value))
    if key in FLOAT_PROPS:
        return ("float", float(value))
    if key in INT_PROPS:
        return ("int", int(value))
    if key in STRING_PROPS:
        return ("string", str(value))
    raise ValueError(f"propriedade nao suportada pelo build: {key}")


def from_tree(node: dict, name: str, parent_is_root: bool) -> Inst:
    if "$path" in node:
        inst = from_path(ROOT / node["$path"], name)
    else:
        cls = node.get("$className")
        if cls is None:
            cls = name if parent_is_root else SPECIAL_CLASSES.get(name, "Folder")
        inst = Inst(cls, name)
    for key, child in node.items():
        if key.startswith("$"):
            continue
        inst.children.append(from_tree(child, key, False))
    return inst


# ---------------------------------------------------------------- escrita

def attributes_blob(attrs: dict[str, object]) -> str:
    """Formato binario que o Roblox usa para guardar atributos."""
    out = bytearray(struct.pack("<I", len(attrs)))
    for key, value in attrs.items():
        kb = key.encode("utf-8")
        out += struct.pack("<I", len(kb)) + kb
        if isinstance(value, bool):
            out += bytes([0x03, 1 if value else 0])
        elif isinstance(value, (int, float)):
            out += bytes([0x06]) + struct.pack("<d", float(value))
        else:
            vb = str(value).encode("utf-8")
            out += bytes([0x02]) + struct.pack("<I", len(vb)) + vb
    return base64.b64encode(bytes(out)).decode("ascii")


def cdata(text: str) -> str:
    # Remove caracteres de controle invisiveis que quebrariam o XML.
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", text)
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def write_prop(lines: list[str], key: str, kind: str, value: object, ind: str) -> None:
    if kind == "source":
        lines.append(f'{ind}<ProtectedString name="Source">{cdata(str(value))}</ProtectedString>')
    elif kind == "string":
        lines.append(f'{ind}<string name="{key}">{escape(str(value))}</string>')
    elif kind == "bool":
        lines.append(f'{ind}<bool name="{key}">{"true" if value else "false"}</bool>')
    elif kind == "float":
        lines.append(f'{ind}<float name="{key}">{value}</float>')
    elif kind == "int":
        lines.append(f'{ind}<int name="{key}">{value}</int>')
    elif kind == "token":
        lines.append(f'{ind}<token name="{key}">{value}</token>')
    elif kind == "vector3":
        x, y, z = value  # type: ignore[misc]
        lines.append(f'{ind}<Vector3 name="size"><X>{x}</X><Y>{y}</Y><Z>{z}</Z></Vector3>')
    elif kind == "cframe":
        pos = value["position"]  # type: ignore[index]
        rot = value.get("orientation", [[1, 0, 0], [0, 1, 0], [0, 0, 1]])  # type: ignore[union-attr]
        parts = [f"<X>{pos[0]}</X><Y>{pos[1]}</Y><Z>{pos[2]}</Z>"]
        for r in range(3):
            for c in range(3):
                parts.append(f"<R{r}{c}>{rot[r][c]}</R{r}{c}>")
        lines.append(f'{ind}<CoordinateFrame name="CFrame">{"".join(parts)}</CoordinateFrame>')
    elif kind == "color":
        r, g, b = (max(0, min(255, round(float(c) * 255))) for c in value)  # type: ignore[union-attr]
        packed = 0xFF000000 | (r << 16) | (g << 8) | b
        lines.append(f'{ind}<Color3uint8 name="Color3uint8">{packed}</Color3uint8>')
    else:
        raise ValueError(kind)


_ref = 0


def write_inst(lines: list[str], inst: Inst, depth: int) -> None:
    global _ref
    _ref += 1
    ind = "\t" * depth
    lines.append(f'{ind}<Item class="{inst.cls}" referent="RBX{_ref:08X}">')
    lines.append(f"{ind}\t<Properties>")
    write_prop(lines, "Name", "string", inst.name, ind + "\t\t")
    # Pecas com superficie lisa (o padrao antigo era "studs").
    if inst.cls in ("Part", "SpawnLocation"):
        write_prop(lines, "TopSurface", "token", 0, ind + "\t\t")
        write_prop(lines, "BottomSurface", "token", 0, ind + "\t\t")
    for key, (kind, value) in inst.props.items():
        if key == "Name":
            continue  # o nome ja foi escrito acima
        write_prop(lines, key, kind, value, ind + "\t\t")
    if inst.attrs:
        lines.append(f'{ind}\t\t<BinaryString name="AttributesSerialize">'
                     f"{attributes_blob(inst.attrs)}</BinaryString>")
    lines.append(f"{ind}\t</Properties>")
    for child in inst.children:
        write_inst(lines, child, depth + 1)
    lines.append(f"{ind}</Item>")


def count(inst: Inst, acc: dict[str, int]) -> None:
    acc[inst.cls] = acc.get(inst.cls, 0) + 1
    for c in inst.children:
        count(c, acc)


def main() -> int:
    project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
    tree = project["tree"]
    services = [from_tree(node, key, True) for key, node in tree.items() if not key.startswith("$")]

    lines = ['<roblox version="4">']
    for svc in services:
        write_inst(lines, svc, 1)
    lines.append("</roblox>")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    totals: dict[str, int] = {}
    for svc in services:
        count(svc, totals)
    print(f"OK -> {OUT.relative_to(ROOT)}")
    for cls, n in sorted(totals.items()):
        print(f"  {cls:22s} {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
