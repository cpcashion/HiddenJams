"""MODE=copy (read-only copy audit) and MODE=promo (sets ONLY promotionalText). No secrets/PII printed."""
import re, sys

PROMO_TEXT = ("How is nobody listening to this? Swipe 30-second previews of underground artists, free. "
              "Works with Apple Music and Spotify. Save gems with a subscription.")
FLAG_RE = re.compile(r"invited|allow-?list|dev(elopment)?\s*mode|testers? only|requires? (a )?spotify|spotify (account|login)|demo (account|login)|sign-?in information|limited to|small number of", re.I)

def versions(get, APP_ID):
    d = get(f"/v1/apps/{APP_ID}/appStoreVersions", {"filter[platform]": "IOS", "limit": 10})
    return (d or {}).get("data", [])

def copy_audit(get, APP_ID, SUB_ID):
    flags = []
    for v in versions(get, APP_ID):
        va = v["attributes"]
        print(f"\n######## version {va['versionString']} state={va['appStoreState']} id={v['id']}")
        locs = get(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations", {"limit": 50})
        for loc in (locs or {}).get("data", []):
            a = loc["attributes"]
            print(f"\n--- [{a['locale']}] localization {loc['id']}")
            for f in ("promotionalText", "keywords", "description", "whatsNew"):
                val = a.get(f) or ""
                print(f"<<{f} ({len(val)} ch)>>\n{val}\n<</{f}>>")
                for line in val.splitlines():
                    if FLAG_RE.search(line): flags.append((va["versionString"], a["locale"], f, line.strip()))
    print("\n######## states")
    s = get(f"/v1/subscriptions/{SUB_ID}")
    print("  subscription", SUB_ID, s and s["data"]["attributes"].get("state"))
    sg = get(f"/v1/apps/{APP_ID}/subscriptionGroups", {"limit": 10})
    for g in (sg or {}).get("data", []):
        print(f"  group {g['id']} {g['attributes'].get('referenceName')!r}")
    rs = get(f"/v1/apps/{APP_ID}/reviewSubmissions", {"filter[platform]": "IOS", "limit": 5, "include": "items"})
    for r in (rs or {}).get("data", []):
        print(f"  reviewSubmission {r['id']} state={r['attributes'].get('state')} submitted={r['attributes'].get('submittedDate')}")
    print("\n######## FLAGGED LINES (limitation / invited / allowlist / dev mode / requires Spotify / demo login)")
    for f in flags: print("  FLAG", f)
    if not flags: print("  none")
    print(f"\nPROMO length check: {len(PROMO_TEXT)}/170")

def promo(get, call, APP_ID, targets):
    assert len(PROMO_TEXT) <= 170
    ok = True
    for v in versions(get, APP_ID):
        vs = v["attributes"]["versionString"]
        if vs not in targets: continue
        locs = get(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations", {"limit": 50})
        for loc in (locs or {}).get("data", []):
            cur = loc["attributes"].get("promotionalText") or ""
            if cur == PROMO_TEXT:
                print(f"  {vs} [{loc['attributes']['locale']}] promotionalText already set"); continue
            _, err = call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}",
                          {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"promotionalText": PROMO_TEXT}}})
            print(f"  {vs} [{loc['attributes']['locale']}] ({v['attributes']['appStoreState']}) set promotionalText ->", err or "ok")
            if err: ok = False
            chk = get(f"/v1/appStoreVersionLocalizations/{loc['id']}")
            print("    readback matches:", (chk or {}).get("data", {}).get("attributes", {}).get("promotionalText") == PROMO_TEXT)
    for v in versions(get, APP_ID):
        print(f"  after: {v['attributes']['versionString']} state={v['attributes']['appStoreState']}")
    sys.exit(0 if ok else 9)
