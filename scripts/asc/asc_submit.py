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
BASE = "https://api.appstoreconnect.apple.com"
HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "assets")
PAYWALL_FILE = os.path.join(ASSETS, "paywall-review.png")
WRITE = MODE == "submit"
REVIEW_VIDEO = os.path.join(ASSETS, "app-review.mp4")
NOTES_PUBKEY = os.path.join(HERE, "notes_pubkey.pem")
AGE_ANSWERS = {"datingAndRelationships": False, "sharedLocation": False}
SPOTIFY_PARA = ("Spotify sign-in is for invited testers only: Spotify limits our app to a small allowlist of accounts. "
                "Please test with Apple Music, which gives the full experience. If you tap Spotify with a non-invited account, "
                "the app shows \"Spotify is for invited testers only\" and offers Continue with Apple Music.")

SCREEN_MANIFEST = os.path.join(HERE, "screenshots.json")
# Manifest format (see screenshots.json):
# { "enabled": bool,                      # false = never touch screenshots, even in submit mode
#   "locales": ["en-US"] | "all",
#   "sets": { "<DISPLAY_TYPE>": [ {"keep": "<substring of existing ASC fileName>"} | {"file": "<name in assets/>"}, ... ] } }
# Each list is the exact final set, in order. Existing screenshots not kept are deleted (after uploads succeed).

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

# ---------------- screenshots (manifest-driven) ----------------
def load_manifest():
    import json
    if not os.path.exists(SCREEN_MANIFEST): return None
    return json.load(open(SCREEN_MANIFEST))

MANIFEST = load_manifest()

def png_size(path):
    with open(path, "rb") as f:
        h = f.read(24)
    return (int.from_bytes(h[16:20], "big"), int.from_bytes(h[20:24], "big")) if h[:8] == b"\x89PNG\r\n\x1a\n" else (None, None)

def screenshot_plan(loc_id, L, apply=False):
    sd = get(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", {"limit": 50})
    sets = {s["attributes"]["screenshotDisplayType"]: s for s in (sd or {}).get("data", [])}
    types = {}
    current = {}
    for t, s in sets.items():
        sc = get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots", {"limit": 20})
        shots = (sc or {}).get("data", [])
        current[t] = shots; types[t] = len(shots)
        desc = [f"{x['attributes'].get('fileName')}({(x['attributes'].get('imageAsset') or {}).get('width')}x{(x['attributes'].get('imageAsset') or {}).get('height')},{state_of(x)})" for x in shots]
        print(f"     {t}: {len(shots)} -> {desc}")
        if any(state_of(x) != "COMPLETE" for x in shots): gap(f"[{L}] {t} has non-COMPLETE screenshots")
    m = MANIFEST
    if not m:
        print("     screenshots.json absent: no screenshot changes planned"); return types
    if not m.get("enabled"):
        print("     screenshots.json enabled=false: screenshot changes on hold (validated only)")
    locs = m.get("locales", "all")
    if locs != "all" and L not in locs:
        return types
    for t, entries in (m.get("sets") or {}).items():
        if t not in sets:
            gap(f"[{L}] manifest set {t} has no existing screenshot set in ASC (creating sets not supported)"); continue
        shots = current[t]
        if not 1 <= len(entries) <= 10: gap(f"[{L}] {t}: manifest needs 1-10 entries"); continue
        plan, ok, kept_ids = [], True, set()
        widths = {(x["attributes"].get("imageAsset") or {}).get("width") for x in shots}
        for e in entries:
            if "keep" in e:
                hit = [x for x in shots if e["keep"].lower() in (x["attributes"].get("fileName") or "").lower() and x["id"] not in kept_ids]
                if len(hit) != 1:
                    gap(f"[{L}] {t}: keep '{e['keep']}' matched {len(hit)} existing screenshots"); ok = False; continue
                kept_ids.add(hit[0]["id"]); plan.append(("keep", hit[0]))
            elif "file" in e:
                path = os.path.join(ASSETS, e["file"])
                if not os.path.exists(path): gap(f"[{L}] {t}: file {e['file']} not in scripts/asc/assets"); ok = False; continue
                w, h = png_size(path)
                if widths and w not in widths and not (t == "APP_IPHONE_67" and w in (1290, 1320)):
                    gap(f"[{L}] {t}: {e['file']} is {w}x{h}, existing set widths {widths}"); ok = False
                plan.append(("upload", path))
            else:
                gap(f"[{L}] {t}: bad manifest entry {e}"); ok = False
        dels = [x for x in shots if x["id"] not in kept_ids]
        print(f"     PLAN {t}: final order = " + ", ".join((x['attributes'].get('fileName') if k == 'keep' else 'NEW ' + os.path.basename(x)) for k, x in plan)
              + f" ; delete {[x['attributes'].get('fileName') for x in dels]}")
        if not ok or not apply or not m.get("enabled"): continue
        s = sets[t]; ordered = []
        for k, x in plan:
            if k == "keep": ordered.append(x["id"]); continue
            nid, err = upload_asset("appScreenshots", "appScreenshotSet", "appScreenshotSets", s["id"], x)
            print(f"     upload {os.path.basename(x)} -> {err or 'COMPLETE'}")
            if err: gap(f"[{L}] {t}: upload {os.path.basename(x)} failed: {err}"); return types
            ordered.append(nid)
        for x in dels:
            _, err = call("DELETE", f"/v1/appScreenshots/{x['id']}")
            print(f"     delete {x['attributes'].get('fileName')} -> {err or 'ok'}")
            if err: gap(f"[{L}] {t}: delete failed {err}"); return types
        _, err = call("PATCH", f"/v1/appScreenshotSets/{s['id']}/relationships/appScreenshots",
                      {"data": [{"type": "appScreenshots", "id": i} for i in ordered]})
        print(f"     reorder -> {err or 'ok'}")
        if err: gap(f"[{L}] {t}: reorder failed {err}")
        sc = get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots", {"limit": 20})
        final = (sc or {}).get("data", [])
        print(f"     FINAL {t}: {[(x['attributes'].get('fileName'), state_of(x)) for x in final]}")
        if [x["id"] for x in final] != ordered: gap(f"[{L}] {t}: final order differs from manifest")
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

# ---------------- review notes ----------------
import re
CRED_RE = re.compile(r"password|passcode|\bpw\b|@|login\s*:|username|user\s*name", re.I)

def transform_notes(notes):
    """Replace every Spotify paragraph with SPOTIFY_PARA (at the first one's position); append if none.
    Returns (new_notes, info dict). Never prints content (public logs)."""
    notes = notes or ""
    if SPOTIFY_PARA in notes:
        return notes, {"changed": False, "reason": "already contains new Spotify paragraph"}
    sep = "\n\n" if "\n\n" in notes else "\n"
    paras = notes.split(sep) if notes else []
    out, idx, removed_cred = [], [], False
    for i, p in enumerate(paras):
        if "spotify" in p.lower():
            idx.append(i)
            if CRED_RE.search(p): removed_cred = True
            if len(idx) == 1: out.append(SPOTIFY_PARA)
        else:
            out.append(p)
    if not idx:
        out.append(SPOTIFY_PARA)
    new = sep.join(x for x in out if x is not None).strip()
    return new, {"changed": True, "paragraphs": len(paras), "spotify_paragraphs": idx,
                 "removed_paragraph_has_possible_credentials": removed_cred,
                 "old_len": len(notes), "new_len": len(new)}

def encrypt_for_box(text):
    """RSA-OAEP(SHA256) wrapped AES-256-GCM; only the private key on the Launch box can read it."""
    import base64, json as _j
    from cryptography.hazmat.primitives import serialization, hashes
    from cryptography.hazmat.primitives.asymmetric import padding
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    pub = serialization.load_pem_public_key(open(NOTES_PUBKEY, "rb").read())
    k = AESGCM.generate_key(256); n = os.urandom(12)
    ct = AESGCM(k).encrypt(n, text.encode(), None)
    ek = pub.encrypt(k, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    b = lambda x: base64.b64encode(x).decode()
    return _j.dumps({"ek": b(ek), "n": b(n), "ct": b(ct)})

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
    st = build and build["attributes"].get("processingState")
    gap(f"PENDING: build {BUILD_NUMBER} not VALID yet (found={bool(build)}, state={st})" if st not in ("FAILED", "INVALID")
        else f"build {BUILD_NUMBER} processing {st}")
    if WRITE:
        print("SUBMIT ABORTED before any writes: build not VALID"); sys.exit(2)
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
        # --- notes update ---
        new_notes, info = transform_notes(a.get("notes"))
        print(f"  NOTES PLAN: {info}")
        if info.get("changed"):
            notes_ok = True
            if len(new_notes) > 4000: gap(f"new review notes {len(new_notes)} > 4000 chars"); notes_ok = False
            if info.get("removed_paragraph_has_possible_credentials"):
                gap("a Spotify paragraph being replaced looks like it contains credentials/contact; needs human review before submit"); notes_ok = False
            print("  NOTES_ENC_CURRENT " + encrypt_for_box(a.get("notes") or ""))
            print("  NOTES_ENC_PROPOSED " + encrypt_for_box(new_notes))
            if WRITE and notes_ok:
                _, err = call("PATCH", f"/v1/appStoreReviewDetails/{rdd['id']}", {"data": {"type": "appStoreReviewDetails", "id": rdd["id"], "attributes": {"notes": new_notes}}})
                print("  update notes ->", err or "ok")
                if err: gap(f"review notes update failed {err}")
        # --- review video attachment ---
        at = get(f"/v1/appStoreReviewDetails/{rdd['id']}/appStoreReviewAttachments")
        atts = (at or {}).get("data", [])
        for x in atts:
            print(f"  attachment {x['attributes'].get('fileName')} {x['attributes'].get('fileSize')}B state={state_of(x)}")
        vname = os.path.basename(REVIEW_VIDEO)
        have_video = any(x["attributes"].get("fileName") == vname and state_of(x) == "COMPLETE" for x in atts)
        if os.path.exists(REVIEW_VIDEO) and not have_video:
            print(f"  VIDEO PLAN: upload {vname} ({os.path.getsize(REVIEW_VIDEO)}B) as App Review attachment")
            if WRITE:
                _, err = upload_asset("appStoreReviewAttachments", "appStoreReviewDetail", "appStoreReviewDetails", rdd["id"], REVIEW_VIDEO)
                print("  upload review video ->", err or "COMPLETE")
                if err: gap(f"review video upload failed: {err}")
        elif have_video:
            print("  VIDEO PLAN: already attached, no change")
        elif not atts:
            note("no review attachment (video) on review detail and no video file in branch")

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
    else:
        missing_keys = [k for k in AGE_ANSWERS if k not in ara]
        if missing_keys: gap(f"age rating API has no fields {missing_keys}")
        change = {k: v for k, v in AGE_ANSWERS.items() if k in ara and ara.get(k) != v}
        print(f"  AGE RATING PLAN: set {change}" if change else "  AGE RATING PLAN: no change")
        if change and WRITE:
            decl_id = ar["data"]["id"]
            _, err = call("PATCH", f"/v1/ageRatingDeclarations/{decl_id}", {"data": {"type": "ageRatingDeclarations", "id": decl_id, "attributes": change}})
            print("  update age rating ->", err or "ok")
            if err: gap(f"age rating update failed {err}")
        rest = [k for k in nulls if k not in AGE_ANSWERS and k not in ("kidsAgeBand", "gracRatingClassificationNumber", "developerAgeRatingInfoUrl")]
        if rest: note(f"age rating has other null fields: {rest}")
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
