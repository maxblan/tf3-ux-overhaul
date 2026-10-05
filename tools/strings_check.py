#!/usr/bin/env python3
"""Lists the mod's translatable strings (_("...") in src) that neither the base game nor the mod's
strings.json translate, for every language in strings.json. Exit code 1 if any are missing.

Usage: tools/strings_check.py [--prune] [--no-game]
  --prune    drop keys from strings.json that the code no longer uses
  --no-game  without the game's catalogs (CI): only check that every language has the same keys and
             that every key is used in the code"""
import glob, gettext, json, re, sys

GAME = "/mnt/c/Program Files (x86)/Steam/steamapps/common/Transport Fever 3/base/strings"
STRINGS = "src/ui_overhaul/strings.json"

used = set()
for path in glob.glob("src/ui_overhaul/content/**/*.lua", recursive=True):
    used.update(re.findall(r'_\(\s*"((?:[^"\\]|\\.)*)"\s*\)', open(path, encoding="utf-8").read()))
# the mod's settings (mod.json params): the game translates their names, tooltips and values
for param in json.load(open("src/ui_overhaul/mod.json", encoding="utf-8")).get("params") or []:
    used.update([param["name"], param["tooltip"], *param["values"]])
mod = json.load(open(STRINGS, encoding="utf-8"))
if "--no-game" in sys.argv:
    problems = []
    keys = {lang: set(mod[lang]) for lang in mod}
    for lang in mod:
        for other in mod:
            for key in sorted(keys[lang] - keys[other]):
                problems.append(f"{other} lacks {key!r} (in {lang})")
    for key in sorted(set().union(*keys.values()) - used):
        problems.append(f"unused key {key!r}")
    for line in problems:
        print(line)
    sys.exit(1 if problems else 0)
missing = []
for lang in mod:
    if lang == "en":
        continue  # English text is the key itself
    try:
        catalog = gettext.GNUTranslations(open(f"{GAME}/{lang}/LC_MESSAGES/base.mo", "rb"))._catalog
        base = {k[0] if isinstance(k, tuple) else k for k in catalog}
    except FileNotFoundError:
        base = set()
    for key in sorted(used):
        if key not in base and key not in mod[lang]:
            missing.append(f"{lang}: {key}")
unused = sorted({k for lang in mod for k in mod[lang]} - used)
if "--prune" in sys.argv:
    for lang in mod:
        mod[lang] = {k: v for k, v in sorted(mod[lang].items()) if k in used}
    json.dump(mod, open(STRINGS, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
    print(f"pruned {len(unused)} unused keys")
for line in missing:
    print("missing", line)
sys.exit(1 if missing else 0)
