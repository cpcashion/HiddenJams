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

EULA_URL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

def _privacy_url(get, APP_ID):
    d = get(f"/v1/apps/{APP_ID}/appInfos")
    infos = (d or {}).get("data", [])
    # prefer the non-live appInfo (the one tied to the version being edited)
    infos.sort(key=lambda ai: (ai["attributes"].get("appStoreState") or ai["attributes"].get("state")) in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION"))
    for ai in infos:
        st = ai["attributes"].get("appStoreState") or ai["attributes"].get("state")
        ld = get(f"/v1/appInfos/{ai['id']}/appInfoLocalizations")
        for l in (ld or {}).get("data", []):
            la = l["attributes"]
            print(f"  appInfo {ai['id']} ({st}) [{la.get('locale')}] privacyPolicyUrl={la.get('privacyPolicyUrl')}")
            if la.get("locale") == "en-US" and la.get("privacyPolicyUrl"):
                return la["privacyPolicyUrl"]
    return None

def eula(get, call, APP_ID, write):
    """Append Terms of Use + Privacy Policy lines to the 1.6.1 description only. write=False -> plan only."""
    pp = _privacy_url(get, APP_ID)
    if not pp:
        print("  BLOCKER: en-US privacyPolicyUrl is not set; not inventing one"); sys.exit(8)
    block = f"Terms of Use: {EULA_URL}\nPrivacy Policy: {pp}"
    ok = True
    for v in versions(get, APP_ID):
        if v["attributes"]["versionString"] != "1.6.1": continue
        print(f"  version 1.6.1 state={v['attributes']['appStoreState']}")
        locs = get(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations", {"limit": 50})
        for loc in (locs or {}).get("data", []):
            L = loc["attributes"]["locale"]; desc = loc["attributes"].get("description") or ""
            if EULA_URL in desc:
                print(f"  [{L}] Terms of Use link already present, skip"); continue
            new = desc.rstrip() + "\n\n" + block
            print(f"  [{L}] PLAN append ({len(desc)} -> {len(new)} ch):\n{block}")
            if len(new) > 4000: print(f"  [{L}] BLOCKER: would exceed 4000"); ok = False; continue
            if not write: continue
            _, err = call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}",
                          {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"description": new}}})
            print(f"  [{L}] PATCH description ->", err or "ok")
            if err: ok = False; continue
            chk = get(f"/v1/appStoreVersionLocalizations/{loc['id']}")
            rb = (chk or {}).get("data", {}).get("attributes", {}).get("description") or ""
            print(f"  [{L}] READBACK matches={rb == new} len={len(rb)}\n<<description>>\n{rb}\n<</description>>")
            if rb != new: ok = False
    for v in versions(get, APP_ID):
        print(f"  after: {v['attributes']['versionString']} state={v['attributes']['appStoreState']}")
    sys.exit(0 if ok else 9)

def resubmit(get, call, APP_ID, RS_ID="07b5db50-fcf3-42d6-9cad-8c6a49bf9548"):
    """Resubmit the UNRESOLVED_ISSUES submission: resolve REJECTED items, then submitted=true. Stops on any doubt."""
    import time
    r = get(f"/v1/reviewSubmissions/{RS_ID}")
    st = r and r["data"]["attributes"].get("state")
    print("  submission state:", st)
    if st != "UNRESOLVED_ISSUES": print("  STOP: not UNRESOLVED_ISSUES"); sys.exit(10)
    it = get(f"/v1/reviewSubmissions/{RS_ID}/items", {"include": "appStoreVersion", "limit": 50})
    items = (it or {}).get("data", [])
    import base64
    def kind(i):
        try:
            raw = base64.urlsafe_b64decode(i + "=" * (-len(i) % 4)).decode().split("|")
            return raw[1]
        except Exception: return "?"
    summary = [(x["id"][:12], kind(x["id"]), x["attributes"].get("state")) for x in items]
    print("  items (id-prefix, kind, state):", summary)
    kinds = {kind(x["id"]) for x in items}
    if not {"6", "18", "19"} <= kinds or any(x["attributes"].get("state") in ("REMOVED",) for x in items):
        print("  STOP: expected version(6) + subscription version(18) + group(19) items, none removed"); sys.exit(11)
    # description must contain EULA link
    for v in versions(get, APP_ID):
        if v["attributes"]["versionString"] != "1.6.1": continue
        locs = get(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations", {"limit": 50})
        for loc in (locs or {}).get("data", []):
            if EULA_URL not in (loc["attributes"].get("description") or ""):
                print(f"  STOP: [{loc['attributes']['locale']}] description lacks Terms of Use link"); sys.exit(12)
    for x in items:
        if x["attributes"].get("state") == "REJECTED":
            _, err = call("PATCH", f"/v1/reviewSubmissionItems/{x['id']}", {"data": {"type": "reviewSubmissionItems", "id": x["id"], "attributes": {"resolved": True}}})
            print(f"  resolve item kind={kind(x['id'])} ->", err or "ok")
            if err: sys.exit(13)
    time.sleep(5)
    _, err = call("PATCH", f"/v1/reviewSubmissions/{RS_ID}", {"data": {"type": "reviewSubmissions", "id": RS_ID, "attributes": {"submitted": True}}})
    print("  submitted=true ->", err or "ok")
    if err: sys.exit(14)
    time.sleep(20)
    r = get(f"/v1/reviewSubmissions/{RS_ID}")
    print("  submission after:", r and r["data"]["attributes"])
    it = get(f"/v1/reviewSubmissions/{RS_ID}/items", {"limit": 50})
    print("  items after:", [(kind(x["id"]), x["attributes"].get("state")) for x in (it or {}).get("data", [])])
    for v in versions(get, APP_ID):
        print(f"  version {v['attributes']['versionString']} state={v['attributes']['appStoreState']}")
    s = get("/v1/subscriptions/6831179739")
    print("  subscription state:", s and s["data"]["attributes"].get("state"))
