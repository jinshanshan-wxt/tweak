#!/usr/bin/env python3
"""Sync loose fallback icon PNGs in the app root to the merged catalog.

Usage: overwrite_loose_icons.py <app_dir> <catalog_dir>

Twitter.app ships loose primary-icon files at its root (e.g.
ProductionAppIcon60x60@2x.png, ProductionAppIcon76x76@2x~ipad.png) that
SpringBoard uses for the home-screen icon. Replacing icons only inside
Assets.car leaves these stale, so the home screen keeps the old art. Here we
overwrite each loose root icon with the matching rendition from the merged
catalog directory scar_merge.py leaves in its --workdir, matched by the icon
asset name (filename prefix) and pixel dimensions.
"""

import json
import os
import shutil
import struct
import sys


def png_dims(path):
    # Scan chunks for IHDR. iOS "CgBI" PNGs prepend a CgBI chunk before IHDR,
    # so we can't assume IHDR is first.
    with open(path, "rb") as f:
        if f.read(8) != b"\x89PNG\r\n\x1a\n":
            return None
        while True:
            head = f.read(8)
            if len(head) < 8:
                return None
            length = struct.unpack(">I", head[:4])[0]
            if head[4:8] == b"IHDR":
                return struct.unpack(">II", f.read(8))
            f.seek(length + 4, 1)  # skip chunk data + CRC


def main():
    if len(sys.argv) not in (3, 4):
        sys.stderr.write("usage: overwrite_loose_icons.py <app_dir> <catalog_dir> [overlay_dir]\n")
        return 2
    app_dir, catalog = sys.argv[1:3]
    masters = {}
    if len(sys.argv) == 4:
        from scar_merge import pad_resize
        for folder, _, files in os.walk(sys.argv[3]):
            for name in files:
                if name.lower().endswith('.png') and not name.startswith('._'):
                    masters[os.path.splitext(name)[0]] = os.path.join(folder, name)

    with open(os.path.join(catalog, "manifest.json")) as fh:
        manifest = json.load(fh)
    facets = {f["attributes"].get("identifier"): f["name"] for f in manifest["facets"]}

    # (asset name, w, h) -> decoded png; and the set of asset names. Atlas
    # crops (links) count via their preview, which holds the final art.
    by_key = {}
    names = set(n for n in facets.values())
    for r in manifest["renditions"]:
        name = facets.get(r["key"].get("identifier"))
        if not name:
            continue
        c = r["content"]
        if c["type"] == "image":
            png, w, h = c["file"], r["width"], r["height"]
        elif c["type"] == "raw-payload" and c.get("preview"):
            png, w, h = c["preview"], r["width"], r["height"]
        elif c["type"] == "link" and c.get("preview"):
            png, (w, h) = c["preview"], c["rect"][2:4]
        else:
            continue
        by_key[(name, w, h)] = os.path.join(catalog, png)

    skipped = []
    replaced_loose = 0
    for f in os.listdir(app_dir):
        if f.startswith("._") or not f.lower().endswith((".png", ".jpg", ".jpeg")):
            continue
        fp = os.path.join(app_dir, f)
        if not os.path.isfile(fp):
            continue
        dims = png_dims(fp)
        if not dims:
            continue
        # Longest asset name that prefixes this loose filename (e.g.
        # "ProductionAppIcon60x60@2x.png" -> "ProductionAppIcon").
        cands = [n for n in names if f.startswith(n)]
        name = max(cands, key=len) if cands else None
        src = by_key.get((name, dims[0], dims[1])) if name else None
        if src:
            shutil.copyfile(src, fp)
        else:
            overlays = [name for name in masters if f.startswith(name)]
            if overlays:
                master = masters[max(overlays, key=len)]
                pad_resize(master, *dims).save(fp)
                replaced_loose += 1
            elif name:
                skipped.append((f, "%dx%d" % dims))

    for f, d in skipped:
        sys.stderr.write("no-match: %s (%s) has no catalog rendition of that size\n" % (f, d))
    print('loose-pack-icons-replaced: %d' % replaced_loose)
    return 0


if __name__ == "__main__":
    sys.exit(main())
