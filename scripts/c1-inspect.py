import json, sys, collections
d = json.load(open("Resources/Localizable.xcstrings", encoding="utf-8"))
s = d["strings"]
print(len(s), d.get("sourceLanguage"))
langs = collections.Counter()
shapes = collections.Counter()
for k, v in s.items():
    for l, loc in v.get("localizations", {}).items():
        langs[l] += 1
        shapes[tuple(sorted(loc.keys()))] += 1
print(langs, shapes)
mode = sys.argv[1] if len(sys.argv) > 1 else ""
if mode == "dump":
    for k in sorted(s):
        loc = s[k]["localizations"]["en"]
        if "stringUnit" in loc:
            print(f"{k}\t{loc['stringUnit']['value']!r}\t// {s[k].get('comment','')}")
        else:
            print(f"{k}\tPLURAL {json.dumps({c:u['stringUnit']['value'] for c,u in loc['variations']['plural'].items()}, ensure_ascii=False)}\t// {s[k].get('comment','')}")
