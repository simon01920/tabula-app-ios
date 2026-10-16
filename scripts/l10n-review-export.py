#!/usr/bin/env python3
"""Export the String Catalogs for native-speaker review (Phase 4 C2, human decision P3-3).

Writes into docs/localization/review/ (deterministic: same catalogs give byte-identical files):
  index.html      one self-contained page: key | where it is used | English | 12 languages, language picker,
                  search, filters (all / needs_review / translated / changed), plural forms as sub-rows
  <lang>.csv      per language, UTF-8 with BOM: key, plural_form, context, english, current, corrected, note
  README.md       how a reviewer works and how the maintainer imports the result
  SOURCE_HASH     sha256 of the catalogs + baseline the files were generated from (staleness check)

Usage:
  python3 scripts/l10n-review-export.py             # regenerate everything
  python3 scripts/l10n-review-export.py --check     # exit 1 if the export is stale (catalog hash differs)
  python3 scripts/l10n-review-export.py --out DIR   # write somewhere else (used by the tests)
Applying reviewer corrections: scripts/l10n-review-import.py.
"""
import argparse
import csv
import io
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "lib"))
from l10n_review import (APPROVE, BASELINE_NAME, HASH_NAME, LANG_NAMES, LANGS, REVIEW_DIR, SOURCE, TARGETS,  # noqa: E402
                         collect, english_ref, is_changed, load_baseline, source_hash)

CSV_COLUMNS = ["key", "plural_form", "context", "english", "current", "corrected", "note"]

HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tabula translation review</title>
<style>
:root{--bg:#f6f7f9;--panel:#fff;--text:#1b1f24;--dim:#5b6570;--line:#d9dee4;--accent:#0b63ce;--ph-bg:#fff1c2;--ph-fg:#7a4b00;
--nr:#b45309;--ok:#1a7f37;--ch:#7c3aed;--head:#eef1f5;--hover:#f1f6fd}
@media (prefers-color-scheme:dark){:root{--bg:#14171b;--panel:#1c2026;--text:#e6e9ed;--dim:#98a2ae;--line:#323942;--accent:#6aaeff;
--ph-bg:#4a3a0a;--ph-fg:#ffd77a;--nr:#f0a45a;--ok:#4ac26b;--ch:#b794f6;--head:#242a31;--hover:#222a35}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:none;padding:0 16px 48px}
h1{font-size:1.35rem;margin:18px 0 6px}
details.intro{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:10px 14px;margin:10px 0}
details.intro summary{cursor:pointer;font-weight:600}
.intro .cols{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:8px}
.intro ol{margin:6px 0 0;padding-left:20px}.intro li{margin:3px 0}
@media (max-width:760px){.intro .cols{grid-template-columns:1fr}}
.bar{position:sticky;top:0;z-index:5;background:var(--bg);padding:10px 0 8px;border-bottom:1px solid var(--line)}
.row1{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
input[type=search],select{font:inherit;color:var(--text);background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:7px 10px}
input[type=search]{flex:1 1 220px;min-width:0}
.langs{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}
.chip{display:inline-flex;align-items:center;gap:5px;border:1px solid var(--line);background:var(--panel);border-radius:999px;padding:3px 10px;cursor:pointer;user-select:none;font-size:.9rem}
.chip input{margin:0}.chip.on{border-color:var(--accent);background:var(--hover)}
button{font:inherit;color:var(--text);background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:6px 10px;cursor:pointer}
button:hover{border-color:var(--accent)}
.count{color:var(--dim);font-size:.85rem;margin:8px 0 0}
table{border-collapse:collapse;width:100%;background:var(--panel);margin-top:10px;table-layout:auto}
th,td{border:1px solid var(--line);padding:6px 8px;vertical-align:top;text-align:left;min-width:150px;overflow-wrap:anywhere}
th{background:var(--head);position:sticky;top:var(--barh,110px);z-index:3;font-size:.85rem}
td.k{min-width:190px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:.8rem}
td.m{min-width:220px;color:var(--dim);font-size:.82rem}
tr.first td{border-top:2px solid var(--line)}
tr:hover td{background:var(--hover)}
.form{display:inline-block;font:600 .72rem system-ui,sans-serif;text-transform:uppercase;letter-spacing:.04em;background:var(--head);border:1px solid var(--line);border-radius:5px;padding:0 6px;color:var(--dim)}
.sub{color:var(--dim)}
.ph{background:var(--ph-bg);color:var(--ph-fg);border-radius:3px;padding:0 2px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:.92em;white-space:nowrap}
.st{display:inline-block;width:.6em;height:.6em;border-radius:50%;margin-right:5px;vertical-align:baseline;background:var(--nr)}
.st.t{background:var(--ok)}
.chg{color:var(--ch);font-size:.7rem;font-weight:700;margin-left:4px}
.none{color:var(--dim)}
tfoot td,.more{border:0;background:none;text-align:center}
footer{color:var(--dim);font-size:.8rem;margin-top:16px}
@media (max-width:700px){
 table,tbody,tr,td{display:block;min-width:0!important;width:100%}
 thead{display:none}
 tr{border:1px solid var(--line);border-radius:8px;margin:0 0 10px;background:var(--panel)}
 td{border:0;border-bottom:1px solid var(--line)}
 td:last-child{border-bottom:0}
 td.m:empty{display:none}
 td[data-label]::before{content:attr(data-label);display:block;font-size:.7rem;font-weight:700;letter-spacing:.04em;text-transform:uppercase;color:var(--dim)}
 tr.first td{border-top:0}
}
</style>
<style id="dyn"></style>
</head>
<body>
<main>
<h1>Tabula translation review</h1>
<details class="intro" open>
<summary>How to review / Ako kontrolovať</summary>
<div class="cols">
<div lang="en"><strong>English</strong>
<ol>
<li>Pick the languages to compare in the bar below (default: English and Slovak). Use the filter for strings that still need review.</li>
<li>Read each string together with <em>Where it is used</em>: it says where the text appears in the app and what the placeholders mean.</li>
<li>This page is read-only. Write corrections in your language's CSV (<code>sk.csv</code> for Slovak): fill the <code>corrected</code> column, optionally <code>note</code>. Write <code>[ok]</code> in <code>corrected</code> to confirm the current text is right; leave it empty to skip the row.</li>
<li>Keep the <span class="ph">%@</span> <span class="ph">%lld</span> <span class="ph">%1$@</span> placeholders (highlighted): same type and same count as in English. Rows that break this are rejected on import.</li>
<li>Plural strings have one row per form (one, few, many, other). Translate each form for the number it stands for; the app picks the form from the number.</li>
<li>Save the CSV as <em>CSV UTF-8</em> (a semicolon separator is fine) and send it back.</li>
</ol></div>
<div lang="sk"><strong>Slovensky</strong>
<ol>
<li>V paneli nižšie vyberte jazyky na porovnanie (predvolene English a Slovenčina). Filtrom zobrazíte texty, ktoré ešte čakajú na kontrolu.</li>
<li>Každý text čítajte spolu so stĺpcom <em>Where it is used</em> (kde sa používa): hovorí, kde sa text v aplikácii zobrazí a čo znamenajú zástupné znaky.</li>
<li>Táto stránka je len na čítanie. Opravy píšte do CSV svojho jazyka (<code>sk.csv</code>): vyplňte stĺpec <code>corrected</code>, voliteľne <code>note</code>. Ak je súčasný text správny, napíšte do <code>corrected</code> hodnotu <code>[ok]</code>; prázdne pole znamená, že riadok preskakujete.</li>
<li>Zachovajte zvýraznené zástupné znaky <span class="ph">%@</span> <span class="ph">%lld</span> <span class="ph">%1$@</span>: rovnaký typ a rovnaký počet ako v angličtine. Riadky, ktoré to porušia, sa pri importe odmietnu.</li>
<li>Množné číslo má riadok pre každý tvar (one, few, many, other). Preložte každý tvar pre číslo, ktoré zastupuje; aplikácia tvar vyberie podľa čísla.</li>
<li>CSV uložte ako <em>CSV UTF-8</em> (bodkočiarka ako oddeľovač je v poriadku) a pošlite späť.</li>
</ol></div>
</div>
</details>

<div class="bar" id="bar">
<div class="row1">
<input type="search" id="q" placeholder="Search key, context or text / Hľadať" aria-label="Search">
<select id="flt" aria-label="Filter">
<option value="all">All / Všetko</option>
<option value="needs_review">Needs review / Čaká na kontrolu</option>
<option value="translated">Translated (reviewed) / Skontrolované</option>
<option value="changed">Changed since last review / Zmenené od poslednej kontroly</option>
</select>
<button type="button" id="all">All languages</button>
<button type="button" id="enonly">English + 1</button>
</div>
<div class="langs" id="langs" role="group" aria-label="Languages"></div>
<div class="count" id="count"></div>
</div>

<table id="tbl">
<thead id="thead"></thead>
<tbody id="body"></tbody>
</table>
<div class="more"><button type="button" id="more" hidden>Show more</button></div>
<footer>Generated from the String Catalogs, source hash __HASH__ (format __VERSION__). Machine translations: none of the languages has been reviewed by a native speaker unless marked as translated.</footer>
</main>
<script id="data" type="application/json">__DATA__</script>
<script>
(function(){
"use strict";
var D=JSON.parse(document.getElementById('data').textContent);
var PAGE=150,shown=PAGE,sel={},lastTarget='sk';
var $=function(i){return document.getElementById(i)};
function store(k,v){try{if(v===undefined)return localStorage.getItem(k);localStorage.setItem(k,v)}catch(e){return null}}
function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}
var PH=/%%|%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDiuUxXoOfeEgGcCsSp]/g;
function hl(s){return esc(s).replace(PH,function(m){return '<span class="ph">'+m+'</span>'})}
function cls(id){return 'l-'+id}

var saved=store('tabula-review-langs'),init=null;
try{init=saved?JSON.parse(saved):null}catch(e){init=null}
D.langs.forEach(function(l){sel[l.id]=init?init.indexOf(l.id)>=0:(l.id==='en'||l.id==='sk')});
sel.en=true;

function buildChips(){
 var box=$('langs');box.innerHTML='';
 D.langs.forEach(function(l){
  var lab=document.createElement('label');lab.className='chip'+(sel[l.id]?' on':'');
  var cb=document.createElement('input');cb.type='checkbox';cb.checked=!!sel[l.id];
  cb.addEventListener('change',function(){sel[l.id]=cb.checked;lab.className='chip'+(cb.checked?' on':'');apply(true)});
  lab.appendChild(cb);lab.appendChild(document.createTextNode(l.name+' ('+l.id+')'));box.appendChild(lab)})}

function buildHead(){
 var h='<tr><th class="k">Key</th><th class="m">Where it is used</th>';
 D.langs.forEach(function(l){h+='<th class="'+cls(l.id)+'" lang="'+l.id+'">'+esc(l.name)+' <span class="sub">'+l.id+'</span></th>'});
 $('thead').innerHTML=h+'</tr>'}

function visibleTargets(){return D.langs.filter(function(l){return l.id!=='en'&&sel[l.id]})}

function matches(e,q,f,vt){
 if(f!=='all'){
  if(!vt.length)return false;
  var any=false,all=true;
  vt.forEach(function(l){(e.v[l.id]||[]).forEach(function(c){
   if(!c)return;
   if(f==='needs_review'&&c[1]===0)any=true;
   if(f==='changed'&&c[2])any=true;
   if(c[1]!==1)all=false})});
  if(f==='translated'){if(!all)return false}else if(!any)return false}
 if(q){
  var hay=(e.k+'\n'+e.m).toLowerCase();
  D.langs.forEach(function(l){if(sel[l.id])(e.v[l.id]||[]).forEach(function(c){if(c)hay+='\n'+c[0].toLowerCase()})});
  if(hay.indexOf(q)<0)return false}
 return true}

function rowHtml(e){
 var out='';
 e.f.forEach(function(form,i){
  out+='<tr class="'+(i===0?'first':'')+'">';
  if(i===0){out+='<td class="k" data-label="Key">'+esc(e.k)+(form?' <span class="form">'+form+'</span>':'')+'</td><td class="m" data-label="Where it is used">'+esc(e.m)+'</td>'}
  else{out+='<td class="k sub" data-label="Plural form">&#8627; <span class="form">'+form+'</span></td><td class="m"></td>'}
  D.langs.forEach(function(l){
   var c=(e.v[l.id]||[])[i];
   out+='<td class="'+cls(l.id)+'" lang="'+l.id+'" data-label="'+esc(l.name)+(form?' / '+form:'')+'">';
   if(!c)out+='<span class="none">&mdash;</span>';
   else{
    if(l.id!=='en')out+='<span class="st '+(c[1]===1?'t':'')+'" title="'+(c[1]===1?'translated (reviewed)':'needs_review')+'"></span>';
    out+=hl(c[0]);
    if(c[2])out+='<span class="chg" title="changed since the last review">changed</span>'}
   out+='</td>'});
  out+='</tr>'});
 return out}

var filtered=[];
function apply(reset){
 var css='';D.langs.forEach(function(l){if(!sel[l.id])css+='.'+cls(l.id)+'{display:none}'});
 $('dyn').textContent=css;
 try{store('tabula-review-langs',JSON.stringify(Object.keys(sel).filter(function(k){return sel[k]})))}catch(e){}
 var q=$('q').value.trim().toLowerCase(),f=$('flt').value,vt=visibleTargets();
 filtered=D.entries.filter(function(e){return matches(e,q,f,vt)});
 if(reset)shown=PAGE;
 render()}

function render(){
 var html='',n=Math.min(shown,filtered.length),rows=0;
 for(var i=0;i<n;i++){html+=rowHtml(filtered[i])}
 filtered.forEach(function(e){rows+=e.f.length});
 $('body').innerHTML=html;
 $('more').hidden=n>=filtered.length;
 $('more').textContent='Show more ('+(filtered.length-n)+' keys left)';
 $('count').textContent=filtered.length+' of '+D.entries.length+' keys ('+rows+' rows) match; showing '+n;
 resize()}

function resize(){document.documentElement.style.setProperty('--barh',$('bar').getBoundingClientRect().height+'px')}

$('q').addEventListener('input',function(){clearTimeout($('q')._t);$('q')._t=setTimeout(function(){apply(true)},180)});
$('flt').addEventListener('change',function(){apply(true)});
$('more').addEventListener('click',function(){shown+=PAGE;render()});
$('all').addEventListener('click',function(){D.langs.forEach(function(l){sel[l.id]=true});buildChips();apply(true)});
$('enonly').addEventListener('click',function(){D.langs.forEach(function(l){sel[l.id]=(l.id==='en'||l.id==='sk')});buildChips();apply(true)});
window.addEventListener('resize',resize);
buildChips();buildHead();apply(true);
})();
</script>
</body>
</html>
"""


def jsonish(obj) -> str:
    """JSON safe to embed in a <script> element."""
    text = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    return (text.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
            .replace("\u2028", "\\u2028").replace("\u2029", "\\u2029"))


def build_html(entries, baseline, digest):
    from l10n_review import EXPORT_VERSION
    data = {"langs": [{"id": lang, "name": LANG_NAMES[lang]} for lang in LANGS], "entries": []}
    for e in entries:
        en = e["cells"][SOURCE]
        v = {}
        for lang in LANGS:
            cells = e["cells"][lang]
            col = []
            for form in e["forms"]:
                if form not in cells:
                    col.append(0)
                    continue
                text, state = cells[form]
                s = 1 if state == "translated" else 0
                ch = 1 if is_changed(baseline, lang, e["cat"], e["key"], form, _en(en, form), text, state) else 0
                col.append([text, s, ch] if ch else [text, s])
            v[lang] = col
        data["entries"].append({"k": e["key"], "m": e["comment"], "f": [f for f in e["forms"]], "v": v})
    html = HTML.replace("__DATA__", jsonish(data)).replace("__HASH__", digest[:16]).replace("__VERSION__", EXPORT_VERSION)
    return html


def _en(en_cells, form):
    return english_ref(en_cells, form)


def build_csv(lang, entries):
    buf = io.StringIO(newline="")
    w = csv.writer(buf, lineterminator="\n", quoting=csv.QUOTE_MINIMAL)
    w.writerow(CSV_COLUMNS)
    rows = 0
    for e in entries:
        cells = e["cells"][lang]
        en = e["cells"][SOURCE]
        for form in e["forms"]:
            if form not in cells:
                continue   # a form this language does not use (its own CLDR categories)
            w.writerow([e["key"], form if form else "", e["comment"], english_ref(en, form), cells[form][0], "", ""])
            rows += 1
    return "\ufeff" + buf.getvalue(), rows


README = """# Translation review

Generated by `scripts/l10n-review-export.py` from `Resources/Localizable.xcstrings` and `Resources/InfoPlist.xcstrings`.
**Every non-English text is a machine translation until a native speaker marks it reviewed.** Do not call any language native quality.

## For a reviewer

1. Open `index.html` in any browser (double-click it, no server needed; it works offline and on a phone).
   Choose the languages to compare (default English + Slovak), search, and filter by status.
   The "Where it is used" column says where each text appears in the app. Format placeholders such as
   `%@`, `%lld` and `%1$@` are highlighted: keep them, with the same type and the same count as in English.
2. Open **your language's CSV** (`sk.csv` for Slovak, `de.csv` for German, ...) in Excel, Numbers or Google Sheets.
   The file is UTF-8 with a BOM, so diacritics, Cyrillic and Japanese/Chinese display correctly.
   Columns: `key`, `plural_form`, `context`, `english`, `current`, `corrected`, `note`.
3. Fill in **`corrected`** only where the current text is wrong or unnatural. Optionally explain in `note`.
   - Leave `corrected` empty: the row is skipped (it stays `needs_review`).
   - Write `[ok]` in `corrected`: the current text is right, mark it reviewed.
   - Write the new text: it replaces the current one and is marked reviewed.
   Do not edit the other columns, do not sort away or delete rows, and do not rename the header.
4. Plural strings have one row per form (`plural_form` = `one`, `few`, `many`, `other`). Translate each form for the numbers it
   covers in your language (the app chooses the form from the number). Never merge the forms into one row.
5. Save as **CSV UTF-8**. A `;` separator (Excel in Slovak, German, Czech ... locales) is fine; so is a missing BOM.
   Send the file back under any name that still starts with the language id (`sk.csv`, `sk-corrected.csv`).

Serbian: review the Cyrillic file `sr.csv`. `sr-Latn.csv` is a mechanical transliteration of it; the import re-derives the Latin
text from every corrected Cyrillic row, so `sr-Latn.csv` is only needed for Latin-only remarks.

## For the maintainer

```
python3 scripts/l10n-review-import.py --dry-run sk.csv     # report only
python3 scripts/l10n-review-import.py sk.csv               # apply
python3 scripts/l10n-review-export.py                      # regenerate this folder
bash scripts/validate.sh                                   # must stay green
```

The import validates every non-empty `corrected` cell: the format specifiers must match the English text in type and count
(`%@`, `%lld`, `%1$lld`, ...); the row must exist (key and plural form); otherwise it is rejected and reported, and the rest still
applies (exit code 1 if anything was rejected). Accepted rows get state `translated` and are recorded in `baseline.json`
(what a reviewer last signed off; it drives the "changed since last review" filter). The catalog is written in the canonical Xcode
form. Then update `docs/localization/REVIEW.md` (reviewer, date, scope) and commit the catalog plus the regenerated folder.

`validate.sh` warns (does not fail) when this folder is older than the catalogs: `SOURCE_HASH` holds a sha256 of both catalogs
and `baseline.json`; `python3 scripts/l10n-review-export.py --check` compares it.
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(REVIEW_DIR))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--catalog-root", help="repository root holding Resources/*.xcstrings (tests)")
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    from l10n_review import ROOT, catalog_paths
    paths = catalog_paths(args.catalog_root or ROOT)
    baseline_path = out / BASELINE_NAME
    digest = source_hash(paths, baseline_path)

    if args.check:
        hp = out / HASH_NAME
        have = hp.read_text(encoding="utf-8").strip() if hp.exists() else ""
        if have != digest:
            print(f"STALE {out}: the review export does not match the catalogs "
                  f"(run: python3 scripts/l10n-review-export.py)")
            return 1
        print(f"OK    {out}: review export matches the catalogs (hash {digest[:12]})")
        return 0

    entries = collect(paths)
    baseline = load_baseline(baseline_path)
    out.mkdir(parents=True, exist_ok=True)
    (out / "index.html").write_bytes(build_html(entries, baseline, digest).encode("utf-8"))
    counts = {}
    for lang in TARGETS:
        text, n = build_csv(lang, entries)
        (out / f"{lang}.csv").write_bytes(text.encode("utf-8"))
        counts[lang] = n
    (out / "README.md").write_bytes(README.encode("utf-8"))
    (out / HASH_NAME).write_bytes((digest + "\n").encode("utf-8"))
    rows_html = sum(len(e["forms"]) for e in entries)
    print(f"wrote {out}: index.html ({len(entries)} keys, {rows_html} rows), "
          f"{len(TARGETS)} CSVs, README.md, {HASH_NAME} {digest[:12]}")
    for lang in TARGETS:
        print(f"  {lang:8} {counts[lang]} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
