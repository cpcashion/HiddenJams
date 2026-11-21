#!/usr/bin/env python3
"""ASC preflight / submit for Hidden Jams. PUBLIC repo: never print secrets or PII.

MODE=preflight (default): strictly read-only. Waits for build, checks everything, prints the
                          planned screenshot / paywall-screenshot changes without making them.
MODE=submit:              applies screenshot swap + paywall review screenshot (if file present),
                          re-runs preflight, and only if clean attaches build, submits subscription
                          and the version for review.
"""
import os, sys, time, hashlib
import jwt, requests

APP_ID = os.environ.get("APP_ID", "6756250527")
BUILD_NUMBER = os.environ.get("BUILD_NUMBER", "90")
EXPECT_VERSION = os.environ.get("EXPECT_VERSION", "1.6.1")
SUB_ID = os.environ.get("SUB_ID", "6831179739")
MODE = os.environ.get("MODE", "preflight")
WAIT_MIN = int(os.environ.get("WAIT_MIN", "0"))
POSITIONAL = os.environ.get("SCREEN_POSITIONAL", "0") == "1"   # fallback: replace slots 2 and 3
BASE = "https://api.appstoreconnect.apple.com"
HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "assets")
PAYWALL_FILE = os.path.join(ASSETS, "paywall-review.png")
WRITE = MODE == "submit"

# Screenshot swap plan: (match keywords in existing fileName, slot index if positional, new file stem)
SWAPS = [
    (("swipe",), 1, "02-best-30-seconds"),   # replaces 02-swipe
    (("rarity",), 2, "01-fun-addictive"),    # replaces 03-rarity
]
# Final order: home, fun-addictive, best-30-seconds, profile, stats
ORDER_KEYS = [("home",), ("fun-addictive",), ("best-30-seconds",), ("profile",), ("stat",)]
SIZE_FOR_WIDTH = {1320: "1320x2868", 1290: "1290x2796"}
SIZE_FOR_TYPE = {"APP_IPHONE_69": "1320x2868", "APP_IPHONE_67": None}  # 67 accepts both; decided by existing width

def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      os.environ["ASC_PRIVATE_KEY"].replace("\\n", "\n"), algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})

def call(method, path, body=None, params=None, ok=(200, 201, 204)):
    if method != "GET" and not WRITE:
        raise RuntimeError(f"BUG: write {method} {path} attempted in read-only mode")
    url = path if path.startswith("http") else BASE + path
    r = requests.request(method, url, params=params, json=body,
                         headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"}, timeout=60)
    if r.status_code not in ok:
        errs = []
        try:
            for e in r.json().get("errors", []):
                errs.append({k: e.get(k) for k in ("status", "code", "title", "detail")})
        except Exception:
            errs = [r.text[:500]]
        return None, (r.status_code, errs)
    return (r.json() if r.content else {}), None

def get(path, params=None):
    d, err = call("GET", path, params=params)
    if err:
        print(f"  ! GET {path} -> {err}")
    return d

gaps, notes = [], []
def gap(m): gaps.append(m); print("  GAP:", m)
def note(m): notes.append(m); print("  note:", m)
def present(v): return "set" if v else "MISSING"
def state_of(x): return (x["attributes"].get("assetDeliveryState") or {}).get("state")

# ---------------- upload helpers (submit mode only) ----------------
def upload_asset(create_type, rel_name, rel_type, rel_id, path):
    data = open(path, "rb").read()
    d, err = call("POST", f"/v1/{create_type}", {"data": {"type": create_type,
                  "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
                  "relationships": {rel_name: {"data": {"type": rel_type, "id": rel_id}}}}})
    if err: return None, f"reserve failed {err}"
    obj = d["data"]
    for op in obj["attributes"].get("uploadOperations") or []:
        hdrs = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        r = requests.request(op["method"], op["url"], headers=hdrs, data=chunk, timeout=120)
        if r.status_code >= 300: return obj["id"], f"chunk upload HTTP {r.status_code}"
    _, err = call("PATCH", f"/v1/{create_type}/{obj['id']}", {"data": {"type": create_type, "id": obj["id"],
                  "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    if err: return obj["id"], f"commit failed {err}"
    for _ in range(40):
        g = get(f"/v1/{create_type}/{obj['id']}")
        st = g and state_of(g["data"])
        if st == "COMPLETE": return obj["id"], None
        if st == "FAILED": return obj["id"], f"asset FAILED {(g['data']['attributes'].get('assetDeliveryState') or {}).get('errors')}"
        time.sleep(6)
    return obj["id"], f"asset not COMPLETE after wait (state={st})"

def match(fname, keys): return any(k in (fname or "").lower() for k in keys)

# ---------------- screenshots ----------------
def screenshot_plan(loc_id, L, apply=False):
    sd = get(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", {"limit": 50})
    types = {}
    for s in (sd or {}).get("data", []):
        t = s["attributes"]["screenshotDisplayType"]
        sc = get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots", {"limit": 20})
        shots = (sc or {}).get("data", [])
        types[t] = len(shots)
        desc = []
        for x in shots:
            ia = x["attributes"].get("imageAsset") or {}
            desc.append(f"{x['attributes'].get('fileName')}({ia.get('width')}x{ia.get('height')},{state_of(x)})")
        print(f"     {t}: {len(shots)} -> {desc}")
        if any(state_of(x) != "COMPLETE" for x in shots): gap(f"[{L}] {t} has non-COMPLETE screenshots")
        if t not in ("APP_IPHONE_69", "APP_IPHONE_67") or not shots:
            continue
        # decide asset size
        w = (shots[0]["attributes"].get("imageAsset") or {}).get("width")
        size = SIZE_FOR_TYPE.get(t) or SIZE_FOR_WIDTH.get(w)
        if not size:
            gap(f"[{L}] {t}: can't map existing width {w} to a new asset size"); continue
        targets = []
        for keys, slot, stem in SWAPS:
            hit = [x for x in shots if match(x["attributes"].get("fileName"), keys)]
            if len(hit) == 1: targets.append((hit[0], stem))
            elif POSITIONAL and len(shots) == 5: targets.append((shots[slot], stem))
            else:
                gap(f"[{L}] {t}: can't identify screenshot to replace with {stem} (matches={len(hit)}); set SCREEN_POSITIONAL=1 if slots are known"); targets = None; break
        if targets is None: continue
        files = {stem: os.path.join(ASSETS, f"{stem}-{size}.png") for _, _, stem in SWAPS}
        missing = [f for f in files.values() if not os.path.exists(f)]
        if missing: gap(f"[{L}] {t}: asset files missing {missing}"); continue
        print(f"     PLAN {t}: " + "; ".join(f"replace {x['attributes'].get('fileName')} -> {os.path.basename(files[stem])}" for x, stem in targets)
              + " ; order home, fun-addictive, best-30-seconds, profile, stats")
        if not apply: continue
        # apply: upload new first, then delete old, then reorder
        new_ids = {}
        for x, stem in targets:
            nid, err = upload_asset("appScreenshots", "appScreenshotSet", "appScreenshotSets", s["id"], files[stem])
            print(f"     upload {os.path.basename(files[stem])} -> {err or 'COMPLETE'}")
            if err: gap(f"[{L}] {t}: upload {stem} failed: {err}"); return types
            new_ids[stem] = nid
        for x, stem in targets:
            _, err = call("DELETE", f"/v1/appScreenshots/{x['id']}")
            print(f"     delete {x['attributes'].get('fileName')} -> {err or 'ok'}")
            if err: gap(f"[{L}] {t}: delete failed {err}"); return types
        sc = get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots", {"limit": 20})
        cur = (sc or {}).get("data", [])
        ordered, used = [], set()
        for keys in ORDER_KEYS:
            for x in cur:
                if x["id"] in used: continue
                fn = x["attributes"].get("fileName") or ""
                stem_hit = any(new_ids.get(k2) == x["id"] for k2 in keys)
                if match(fn, keys) or stem_hit:
                    ordered.append(x["id"]); used.add(x["id"]); break
        ordered += [x["id"] for x in cur if x["id"] not in used]
        _, err = call("PATCH", f"/v1/appScreenshotSets/{s['id']}/relationships/appScreenshots",
                      {"data": [{"type": "appScreenshots", "id": i} for i in ordered]})
        print(f"     reorder -> {err or 'ok'}")
        sc = get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots", {"limit": 20})
        final = (sc or {}).get("data", [])
        print(f"     FINAL {t}: {[ (x['attributes'].get('fileName'), state_of(x)) for x in final ]}")
        if any(state_of(x) != "COMPLETE" for x in final): gap(f"[{L}] {t}: post-swap screenshots not all COMPLETE")
    return types

# ---------------- paywall review screenshot ----------------
def paywall_step(apply=False):
    shot = get(f"/v1/subscriptions/{SUB_ID}/appStoreReviewScreenshot")
    cur = shot.get("data") if shot else None
    have_file = os.path.exists(PAYWALL_FILE)
    print(f"  paywall file in branch: {have_file}; current review screenshot: {('present ' + str(state_of(cur))) if cur else 'MISSING'}")
    if not have_file:
        return cur
    print("  PLAN: upload paywall-review.png as subscription review screenshot" + (" (replacing existing)" if cur else ""))
    if not apply: return cur
    if cur:
        _, err = call("DELETE", f"/v1/subscriptionAppStoreReviewScreenshots/{cur['id']}")
        print("  delete old review screenshot ->", err or "ok")
    nid, err = upload_asset("subscriptionAppStoreReviewScreenshots", "subscription", "subscriptions", SUB_ID, PAYWALL_FILE)
    print("  upload paywall review screenshot ->", err or "COMPLETE")
    if err: gap(f"paywall review screenshot upload failed: {err}")
    shot = get(f"/v1/subscriptions/{SUB_ID}/appStoreReviewScreenshot")
    return shot.get("data") if shot else None

# ================= build =================
print(f"== MODE={MODE}  build {BUILD_NUMBER}  expected version {EXPECT_VERSION}")
d = get("/v1/builds", {"filter[app]": APP_ID, "sort": "-uploadedDate", "limit": 6, "include": "preReleaseVersion"})
pre = {i["id"]: i for i in (d or {}).get("included", [])}
print("  latest builds:")
for b in (d or {}).get("data", []):
    p = b["relationships"]["preReleaseVersion"]["data"]
    print(f"    {b['attributes']['version']} ({pre.get(p['id'],{}).get('attributes',{}).get('version') if p else '?'}) {b['attributes'].get('processingState')} uploaded={b['attributes'].get('uploadedDate')}")

deadline = time.time() + WAIT_MIN * 60
build, mv = None, None
while True:
    d = get("/v1/builds", {"filter[app]": APP_ID, "filter[version]": BUILD_NUMBER, "include": "preReleaseVersion", "limit": 5})
    if d and d.get("data"):
        build = d["data"][0]
        pre = {i["id"]: i for i in d.get("included", [])}
        a = build["attributes"]
        prv = build["relationships"]["preReleaseVersion"]["data"]
        mv = pre.get(prv["id"], {}).get("attributes", {}).get("version") if prv else None
        print(f"  build {BUILD_NUMBER}: id={build['id']} state={a.get('processingState')} marketing={mv} uploaded={a.get('uploadedDate')} expired={a.get('expired')} nonExemptEnc={a.get('usesNonExemptEncryption')}")
        if a.get("processingState") in ("VALID", "FAILED", "INVALID"): break
    else:
        print(f"  build {BUILD_NUMBER} not found yet")
    if time.time() > deadline: break
    time.sleep(120)

if not build or build["attributes"].get("processingState") != "VALID":
    gap(f"build {BUILD_NUMBER} not VALID (found={bool(build)}, state={build and build['attributes'].get('processingState')})")
else:
    if mv != EXPECT_VERSION: gap(f"build marketing version {mv} != {EXPECT_VERSION}")
    if build["attributes"].get("usesNonExemptEncryption") is None:
        note("usesNonExemptEncryption null; Info.plist declares ITSAppUsesNonExemptEncryption=false -> submit sets false")

# ================= version =================
print("== App Store version")
d = get(f"/v1/apps/{APP_ID}/appStoreVersions", {"filter[platform]": "IOS", "limit": 10})
versions = d.get("data", []) if d else []
for v in versions:
    print(f"  {v['id']} {v['attributes']['versionString']} {v['attributes']['appStoreState']} release={v['attributes'].get('releaseType')}")
editable = [v for v in versions if v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")]
ver = editable[0] if editable else None
if not ver:
    gap("no editable App Store version found")
else:
    va = ver["attributes"]
    if va["versionString"] != EXPECT_VERSION: gap(f"editable version string {va['versionString']} != {EXPECT_VERSION}")
    print(f"  editable: {va['versionString']} copyright={present(va.get('copyright'))} releaseType={va.get('releaseType')}")
    if not va.get("copyright"): gap("version copyright missing")
    bd = get(f"/v1/appStoreVersions/{ver['id']}/build")
    cur = bd.get("data") if bd else None
    print(f"  currently attached build: {cur and cur['attributes'].get('version')}")

    print("== Version localizations + screenshots")
    d = get(f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations", {"limit": 50})
    for loc in (d or {}).get("data", []):
        a = loc["attributes"]; L = a["locale"]
        print(f"  [{L}] description={len(a.get('description') or '')}ch keywords={len(a.get('keywords') or '')}ch supportUrl={present(a.get('supportUrl'))} marketingUrl={present(a.get('marketingUrl'))} promo={len(a.get('promotionalText') or '')}ch whatsNew={len(a.get('whatsNew') or '')}ch")
        for f in ("description", "keywords", "supportUrl"):
            if not a.get(f): gap(f"[{L}] {f} missing")
        types = screenshot_plan(loc["id"], L, apply=WRITE)
        if not any(types.get(t, 0) > 0 for t in ("APP_IPHONE_67", "APP_IPHONE_65", "APP_IPHONE_69")):
            gap(f"[{L}] no 6.5/6.7/6.9-inch iPhone screenshots")
        pv = get(f"/v1/appStoreVersionLocalizations/{loc['id']}/appPreviewSets", {"limit": 20})
        for s in (pv or {}).get("data", []):
            print(f"     preview set {s['attributes'].get('previewType')}")

    print("== Review details")
    rd = get(f"/v1/appStoreVersions/{ver['id']}/appStoreReviewDetail")
    rdd = rd.get("data") if rd else None
    if not rdd:
        gap("appStoreReviewDetail missing")
    else:
        a = rdd["attributes"]
        print(f"  contactFirstName={present(a.get('contactFirstName'))} contactLastName={present(a.get('contactLastName'))} contactPhone={present(a.get('contactPhone'))} contactEmail={present(a.get('contactEmail'))}")
        print(f"  demoAccountRequired={a.get('demoAccountRequired')} demoName={present(a.get('demoAccountName'))} demoPassword={present(a.get('demoAccountPassword'))} notes={len(a.get('notes') or '')}ch")
        for f in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
            if not a.get(f): gap(f"review contact {f} missing")
        if a.get("demoAccountRequired") and not (a.get("demoAccountName") and a.get("demoAccountPassword")):
            gap("demo account required but name/password missing")
        if not a.get("notes"): gap("review notes empty")
        at = get(f"/v1/appStoreReviewDetails/{rdd['id']}/appStoreReviewAttachments")
        atts = (at or {}).get("data", [])
        for x in atts:
            print(f"  attachment {x['attributes'].get('fileName')} {x['attributes'].get('fileSize')}B state={state_of(x)}")
        if not atts: note("no review attachment (video) on review detail")

# ================= app info =================
print("== App info / age rating / category")
d = get(f"/v1/apps/{APP_ID}/appInfos", {"include": "primaryCategory"})
for ai in (d or {}).get("data", []):
    a = ai["attributes"]
    st = a.get("appStoreState") or a.get("state")
    pc = (ai["relationships"].get("primaryCategory") or {}).get("data")
    print(f"  appInfo {ai['id']} state={st} ageRating={a.get('appStoreAgeRating')} primaryCategory={pc and pc['id']}")
    if st in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION"): continue
    if not pc: gap("primary category missing")
    ar = get(f"/v1/appInfos/{ai['id']}/ageRatingDeclaration")
    ara = (ar or {}).get("data", {}).get("attributes", {}) if ar else {}
    nulls = [k for k, v in ara.items() if v is None]
    print(f"  ageRating null fields: {nulls}")
    if not ara: gap("age rating declaration missing")
    elif nulls: note(f"age rating has null fields: {nulls}")
    ld = get(f"/v1/appInfos/{ai['id']}/appInfoLocalizations")
    for l in (ld or {}).get("data", []):
        la = l["attributes"]
        print(f"  [{la['locale']}] name={la.get('name')!r} subtitle={present(la.get('subtitle'))} privacyPolicyUrl={present(la.get('privacyPolicyUrl'))}")
        if not la.get("privacyPolicyUrl"): gap(f"[{la['locale']}] privacy policy URL missing")
        if not la.get("name"): gap(f"[{la['locale']}] name missing")

# ================= pricing / availability =================
print("== Pricing / availability")
ps = get(f"/v1/apps/{APP_ID}/appPriceSchedule", {"include": "baseTerritory,manualPrices"})
if ps and ps.get("data"):
    bt = (ps["data"]["relationships"].get("baseTerritory") or {}).get("data")
    mp = [i for i in ps.get("included", []) if i["type"] == "appPrices"]
    print(f"  baseTerritory={bt and bt['id']} manualPrices={len(mp)}")
    if not mp: gap("app price schedule has no prices")
else:
    gap("app price schedule missing")
av = get(f"/v1/apps/{APP_ID}/appAvailabilityV2")
if av and av.get("data"):
    ta = get(f"/v2/appAvailabilities/{av['data']['id']}/territoryAvailabilities", {"limit": 200, "include": "territory"})
    avail = [t["relationships"]["territory"]["data"]["id"] for t in (ta or {}).get("data", []) if t["attributes"].get("available")]
    print(f"  availableInNewTerritories={av['data']['attributes'].get('availableInNewTerritories')} available={avail}")
    if not avail: gap("no territories available")
else:
    gap("app availability not set")

# ================= subscription =================
print("== Subscription")
sub_ready = False
s = get(f"/v1/subscriptions/{SUB_ID}")
if s and s.get("data"):
    a = s["data"]["attributes"]
    print(f"  {a.get('productId')} name={a.get('name')!r} state={a.get('state')} period={a.get('subscriptionPeriod')} familySharable={a.get('familySharable')} reviewNote={len(a.get('reviewNote') or '')}ch")
    sd = paywall_step(apply=WRITE)
    locs = get(f"/v1/subscriptions/{SUB_ID}/subscriptionLocalizations")
    for l in (locs or {}).get("data", []):
        la = l["attributes"]; print(f"  loc [{la.get('locale')}] name={present(la.get('name'))} desc={present(la.get('description'))} state={la.get('state')}")
    if not (locs or {}).get("data"): gap("subscription has no localization")
    pr = get(f"/v1/subscriptions/{SUB_ID}/prices", {"include": "territory", "limit": 200})
    terr = sorted({p["relationships"]["territory"]["data"]["id"] for p in (pr or {}).get("data", [])})
    print(f"  price territories={terr}")
    if not terr: gap("subscription has no prices")
    sa = get(f"/v1/subscriptions/{SUB_ID}/subscriptionAvailability")
    if sa and sa.get("data"): print(f"  subscriptionAvailability newTerritories={sa['data']['attributes'].get('availableInNewTerritories')}")
    else: note("subscriptionAvailability not set")
    g = get(f"/v1/subscriptions/{SUB_ID}/group")
    if g and g.get("data"):
        gl = get(f"/v1/subscriptionGroups/{g['data']['id']}/subscriptionGroupLocalizations")
        for l in (gl or {}).get("data", []):
            print(f"  group loc [{l['attributes'].get('locale')}] name={present(l['attributes'].get('name'))} state={l['attributes'].get('state')}")
        if not (gl or {}).get("data"): gap("subscription group has no localization")
    if WRITE: s = get(f"/v1/subscriptions/{SUB_ID}")
    st = s["data"]["attributes"].get("state")
    if st == "READY_TO_SUBMIT": sub_ready = True
    elif st in ("WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED"): note(f"subscription already {st}")
    elif st == "MISSING_METADATA" and not sd and not WRITE and os.path.exists(PAYWALL_FILE):
        note("subscription MISSING_METADATA; paywall screenshot file present and would be uploaded in submit mode")
    else:
        gap(f"subscription state {st} (need READY_TO_SUBMIT){'; review screenshot missing' if not sd else ''}")
else:
    gap("subscription not readable")

print("== Existing review submissions")
rs = get(f"/v1/apps/{APP_ID}/reviewSubmissions", {"filter[platform]": "IOS", "limit": 10})
open_rs = None
for r in (rs or {}).get("data", []):
    print(f"  {r['id']} state={r['attributes'].get('state')} submitted={r['attributes'].get('submittedDate')}")
    if r["attributes"].get("state") == "READY_FOR_REVIEW" and not open_rs: open_rs = r
    if r["attributes"].get("state") in ("WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"):
        note(f"existing review submission in state {r['attributes'].get('state')}")

note("App Privacy publish status and Paid Apps agreement/tax status are not exposed by the ASC API; Apple validates them at submit time")

print("\n==== PREFLIGHT SUMMARY ====")
print(f"gaps={len(gaps)}"); [print(" -", g) for g in gaps]
print("notes:"); [print(" -", n) for n in notes]

if not WRITE:
    print("read-only run complete; no writes made"); sys.exit(0)
if gaps:
    print("SUBMIT ABORTED: preflight gaps present"); sys.exit(2)

# ================= submit =================
print("\n== SUBMIT")
if build["attributes"].get("usesNonExemptEncryption") is None:
    _, err = call("PATCH", f"/v1/builds/{build['id']}", {"data": {"type": "builds", "id": build["id"], "attributes": {"usesNonExemptEncryption": False}}})
    print("  set usesNonExemptEncryption=false:", err or "ok")
    if err: sys.exit(3)
_, err = call("PATCH", f"/v1/appStoreVersions/{ver['id']}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
print("  attach build:", err or "ok")
if err: sys.exit(3)
if sub_ready:
    _, err = call("POST", "/v1/subscriptionSubmissions", {"data": {"type": "subscriptionSubmissions", "relationships": {"subscription": {"data": {"type": "subscriptions", "id": SUB_ID}}}}})
    print("  subscriptionSubmission:", err or "ok")
    if err: sys.exit(4)
if open_rs:
    rsid = open_rs["id"]; print("  reusing reviewSubmission", rsid)
else:
    d, err = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"}, "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
    print("  create reviewSubmission:", err or "ok")
    if err: sys.exit(5)
    rsid = d["data"]["id"]
items = get(f"/v1/reviewSubmissions/{rsid}/items", {"include": "appStoreVersion"})
have = any(((i["relationships"].get("appStoreVersion") or {}).get("data") or {}).get("id") == ver["id"] for i in (items or {}).get("data", []))
if not have:
    _, err = call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rsid}}, "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
    print("  add version item:", err or "ok")
    if err: sys.exit(6)
_, err = call("PATCH", f"/v1/reviewSubmissions/{rsid}", {"data": {"type": "reviewSubmissions", "id": rsid, "attributes": {"submitted": True}}})
print("  submitted=true:", err or "ok")
if err: sys.exit(7)
time.sleep(20)
r = get(f"/v1/reviewSubmissions/{rsid}"); v = get(f"/v1/appStoreVersions/{ver['id']}"); s = get(f"/v1/subscriptions/{SUB_ID}")
print(f"  reviewSubmission state={r and r['data']['attributes'].get('state')} submittedDate={r and r['data']['attributes'].get('submittedDate')}")
print(f"  version state={v and v['data']['attributes'].get('appStoreState')}")
print(f"  subscription state={s and s['data']['attributes'].get('state')}")
