#!/usr/bin/env python3
"""Pick a simulator runtime + device type from the FULL `xcrun simctl list -j` output (CI screenshot job).

Never call `xcrun simctl list -j runtimes devicetypes`: simctl accepts ONE section name and treats the next word
as a search term, so that call returns `"runtimes": []` (qa-reviewer finding 2026-10-06). Pass the full JSON.

Usage
  xcrun simctl list -j > sim.json
  python3 scripts/sim_pick.py sim.json --platform iOS [--device "iPhone 17 Pro Max"]
      -> SIM_RUNTIME=…  SIM_RUNTIME_NAME=…  SIM_TYPE=…  SIM_NAME=…        (KEY=value lines, values may contain spaces)
  python3 scripts/sim_pick.py sim.json --platform watchOS
      -> WATCH_RUNTIME=…  WATCH_RUNTIME_NAME=…  WATCH_TYPE=…  WATCH_NAME=…
  python3 scripts/sim_pick.py --self-test

Rules: newest *available* runtime of the platform; device types from that runtime's `supportedDeviceTypes`
(fallback: `devicetypes` filtered by product family and min/max runtime version). iOS default = the "Pro Max" with
the highest model number (else the highest-numbered iPhone); watchOS default = highest model number, then size.
An explicit --device must be supported by the chosen runtime. Stdlib only.
"""
import argparse
import json
import re
import sys

FAMILY = {"iOS": "iPhone", "watchOS": "Apple Watch"}
PREFIX = {"iOS": "SIM", "watchOS": "WATCH"}


def version_tuple(text):
    return tuple(int(x) for x in re.findall(r"\d+", str(text))) or (0,)


def platform_of(runtime):
    return runtime.get("platform") or str(runtime.get("name", "")).split(" ")[0]


def numbers(name):
    return [int(x) for x in re.findall(r"\d+", name)] or [0]


def pick(data, platform, device=""):
    if "runtimes" not in data or "devicetypes" not in data:
        raise SystemExit("error: need the full `xcrun simctl list -j` output (keys runtimes + devicetypes)")
    runtimes = [r for r in data["runtimes"] if platform_of(r) == platform and r.get("isAvailable") is True]
    if not runtimes:
        raise SystemExit(f"error: no available {platform} simulator runtime "
                         f"({len(data['runtimes'])} runtimes listed in total)")
    runtime = max(runtimes, key=lambda r: version_tuple(r.get("version")))
    family = FAMILY[platform]
    types = runtime.get("supportedDeviceTypes")
    if not types:
        v = version_tuple(runtime.get("version"))
        types = [t for t in data["devicetypes"]
                 if (t.get("productFamily") == family or t["name"].startswith(family))
                 and version_tuple(t.get("minRuntimeVersionString", "0")) <= v
                 <= version_tuple(t.get("maxRuntimeVersionString", "999"))]
    candidates = [t for t in types if t.get("productFamily", family) == family and t["name"].startswith(family)]
    if not candidates:
        raise SystemExit(f"error: {runtime['name']} supports no {family} device types")
    if device:
        chosen = next((t for t in candidates if t["name"] == device), None)
        if chosen is None:
            raise SystemExit(f"error: device type {device!r} not supported by {runtime['name']}: "
                             f"{sorted(t['name'] for t in candidates)}")
    elif platform == "iOS":
        chosen = max(candidates, key=lambda t: ("Pro Max" in t["name"], numbers(t["name"])[0], t["name"]))
    else:
        chosen = max(candidates, key=lambda t: (numbers(t["name"]), t["name"]))
    p = PREFIX[platform]
    return {f"{p}_RUNTIME": runtime["identifier"], f"{p}_RUNTIME_NAME": runtime["name"],
            f"{p}_TYPE": chosen["identifier"], f"{p}_NAME": chosen["name"]}


# --- self-test: shaped like real `xcrun simctl list -j` output (devicetypes / runtimes / devices / pairs) ---------

def _dt(name, family, lo="26.0", hi="65535.255.255"):
    ident = "com.apple.CoreSimulator.SimDeviceType." + re.sub(r"[^A-Za-z0-9]+", "-", name).strip("-")
    return {"productFamily": family, "bundlePath": f"/Library/Developer/CoreSimulator/Profiles/DeviceTypes/{name}.simdevicetype",
            "maxRuntimeVersion": 4294967295, "maxRuntimeVersionString": hi, "identifier": ident,
            "modelIdentifier": "x", "minRuntimeVersionString": lo, "minRuntimeVersion": 1703936, "name": name}


def _short(t):
    return {k: t[k] for k in ("bundlePath", "name", "identifier", "productFamily")}


def _rt(platform, version, build, types, available=True):
    r = {"bundlePath": f"/Library/Developer/CoreSimulator/Volumes/{platform}_{build}/{platform} {version}.simruntime",
         "buildversion": build, "platform": platform, "runtimeRoot": "/…/RuntimeRoot",
         "identifier": f"com.apple.CoreSimulator.SimRuntime.{platform}-{version.replace('.', '-')}",
         "version": version, "isInternal": False, "isAvailable": available, "name": f"{platform} {version}",
         "supportedDeviceTypes": [_short(t) for t in types]}
    if not available:
        r["availabilityError"] = "runtime profile not found using \"System\" match policy"
    return r


def _sample():
    ip = {n: _dt(n, "iPhone") for n in ("iPhone 16 Pro Max", "iPhone 16e", "iPhone 17", "iPhone 17 Pro",
                                        "iPhone 17 Pro Max", "iPhone Air")}
    ip["iPhone 18 Pro Max"] = _dt("iPhone 18 Pro Max", "iPhone", lo="27.2")
    ipad = _dt("iPad Pro 13-inch (M5)", "iPad")
    w = {n: _dt(n, "Apple Watch") for n in ("Apple Watch Series 7 (45mm)", "Apple Watch Series 11 (42mm)",
                                            "Apple Watch Series 11 (46mm)", "Apple Watch SE 3 (44mm)",
                                            "Apple Watch Ultra 3 (49mm)")}
    tv = _dt("Apple TV 4K (3rd generation)", "Apple TV")
    devicetypes = list(ip.values()) + [ipad] + list(w.values()) + [tv]
    runtimes = [
        _rt("iOS", "26.4", "23E244", [ip["iPhone 16 Pro Max"], ip["iPhone 17 Pro Max"], ip["iPhone 17"], ipad]),
        _rt("iOS", "27.0", "24A430", [ip["iPhone 17"], ip["iPhone Air"], ip["iPhone 17 Pro"], ip["iPhone 17 Pro Max"],
                                      ip["iPhone 16 Pro Max"], ip["iPhone 16e"], ipad]),
        _rt("iOS", "27.2", "24C5089c", [ip["iPhone 18 Pro Max"], ip["iPhone 17 Pro Max"]], available=False),
        _rt("watchOS", "26.4", "23T241", [w["Apple Watch Series 7 (45mm)"], w["Apple Watch Series 11 (46mm)"]]),
        _rt("watchOS", "27.0", "24R360", [w["Apple Watch Series 11 (42mm)"], w["Apple Watch Series 11 (46mm)"],
                                          w["Apple Watch SE 3 (44mm)"], w["Apple Watch Ultra 3 (49mm)"]]),
        _rt("tvOS", "27.0", "24J360", [tv]),
    ]
    devices = {r["identifier"]: [{"udid": "00000000-0000-0000-0000-00000000000%d" % i, "isAvailable": True,
                                  "deviceTypeIdentifier": t["identifier"], "state": "Shutdown", "name": t["name"]}
                                 for i, t in enumerate(r["supportedDeviceTypes"][:2])] for r in runtimes}
    return {"devicetypes": devicetypes, "runtimes": runtimes, "devices": devices, "pairs": {}}


def self_test():
    sample, failures = _sample(), 0

    def expect(label, fn, want):
        nonlocal failures
        try:
            got = fn()
        except SystemExit as e:
            got = f"SystemExit: {e}"
        ok = want(got) if callable(want) else got == want
        failures += 0 if ok else 1
        print(f"{'OK  ' if ok else 'FAIL'} {label}: {got}")

    expect("iOS default = newest available runtime + largest Pro Max", lambda: pick(sample, "iOS"),
           lambda g: isinstance(g, dict) and g["SIM_RUNTIME_NAME"] == "iOS 27.0" and g["SIM_NAME"] == "iPhone 17 Pro Max")
    expect("unavailable iOS 27.2 runtime (and its iPhone 18 Pro Max) ignored", lambda: pick(sample, "iOS")["SIM_NAME"],
           "iPhone 17 Pro Max")
    expect("override honoured", lambda: pick(sample, "iOS", "iPhone 16 Pro Max")["SIM_NAME"], "iPhone 16 Pro Max")
    expect("unknown override fails loudly", lambda: pick(sample, "iOS", "iPhone 99"),
           lambda g: isinstance(g, str) and "not supported by iOS 27.0" in g)
    expect("watchOS = newest runtime, highest model then size", lambda: pick(sample, "watchOS"),
           lambda g: isinstance(g, dict) and g["WATCH_RUNTIME_NAME"] == "watchOS 27.0"
           and g["WATCH_NAME"] == "Apple Watch Series 11 (46mm)")
    search_term_shape = {"devicetypes": sample["devicetypes"], "runtimes": []}   # what `list -j runtimes devicetypes` gives
    expect("empty runtimes (old search-term bug) fails loudly", lambda: pick(search_term_shape, "iOS"),
           lambda g: isinstance(g, str) and "no available iOS simulator runtime" in g)
    expect("partial JSON rejected", lambda: pick({"runtimes": sample["runtimes"]}, "iOS"),
           lambda g: isinstance(g, str) and "full `xcrun simctl list -j`" in g)
    no_supported = json.loads(json.dumps(sample))
    for r in no_supported["runtimes"]:
        r.pop("supportedDeviceTypes")
    expect("fallback without supportedDeviceTypes respects minRuntimeVersion", lambda: pick(no_supported, "iOS")["SIM_NAME"],
           "iPhone 17 Pro Max")
    print(f"sim_pick self-test: {'all passed' if not failures else f'{failures} FAILED'}")
    return failures


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("json", nargs="?")
    ap.add_argument("--platform", choices=sorted(FAMILY), default="iOS")
    ap.add_argument("--device", default="")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        sys.exit(1 if self_test() else 0)
    if not a.json:
        ap.error("path to `xcrun simctl list -j` output required")
    with open(a.json, encoding="utf-8") as f:
        result = pick(json.load(f), a.platform, a.device.strip())
    for k, v in result.items():
        print(f"{k}={v}")


if __name__ == "__main__":
    main()
