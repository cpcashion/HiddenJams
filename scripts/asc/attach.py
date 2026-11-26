"""MODE=attach: on the REJECTED 1.6.1 version, attach build BUILD_NUMBER and swap the per-build
review-notes line. Never resubmits, never resolves items, never cancels the submission.
MODE=attach-plan: same checks, read-only (also the post-attach verification).
PUBLIC repo: the notes body is never printed (only lengths / presence of the public build lines)."""
import sys, time

RS_ID = "07b5db50-fcf3-42d6-9cad-8c6a49bf9548"
OLD_LINE = "Build 92 fixes the launch crash seen on iOS 27.2.1 in build 91."
NEW_LINE = ("Build 94: Hidden Jams Unlimited ($1.99/month) is always available from Profile > Hidden Jams Unlimited "
            "(first card). Onboarding: tap Next x4, Continue with Apple Music (no subscription or library needed), "
            "Next through the taste profile, Start digging, then the Profile tab.")

def run(get, call, APP_ID, BUILD_NUMBER, write):
    print(f"== MODE={'attach' if write else 'attach-plan'}  build {BUILD_NUMBER}  submission {RS_ID}")
    r = get(f"/v1/reviewSubmissions/{RS_ID}")
    st = r and r["data"]["attributes"].get("state")
    print("  submission state:", st)
    if st != "UNRESOLVED_ISSUES":
        print("  STOP: submission is not UNRESOLVED_ISSUES"); sys.exit(20)
    vs = get(f"/v1/apps/{APP_ID}/appStoreVersions", {"filter[platform]": "IOS", "filter[versionString]": "1.6.1", "limit": 5})
    ver = ((vs or {}).get("data") or [None])[0]
    if not ver: print("  STOP: version 1.6.1 not found"); sys.exit(21)
    print(f"  version 1.6.1 id={ver['id']} state={ver['attributes'].get('appStoreState')}")
    d = get("/v1/builds", {"filter[app]": APP_ID, "filter[version]": BUILD_NUMBER, "filter[preReleaseVersion.version]": "1.6.1", "limit": 5})
    build = ((d or {}).get("data") or [None])[0]
    if not build: print(f"  STOP: build {BUILD_NUMBER} not found"); sys.exit(22)
    ba = build["attributes"]
    print(f"  build {BUILD_NUMBER}: id={build['id']} state={ba.get('processingState')} expired={ba.get('expired')} nonExemptEnc={ba.get('usesNonExemptEncryption')}")
    if ba.get("processingState") != "VALID" or ba.get("expired"):
        print("  STOP: build not VALID"); sys.exit(23)

    cur = get(f"/v1/appStoreVersions/{ver['id']}/build")
    cur_v = (((cur or {}).get("data") or {}).get("attributes") or {}).get("version")
    print("  currently attached build:", cur_v)

    # --- export compliance ---
    if ba.get("usesNonExemptEncryption") is None:
        print("  PLAN: set usesNonExemptEncryption=false")
        if write:
            _, err = call("PATCH", f"/v1/builds/{build['id']}", {"data": {"type": "builds", "id": build["id"], "attributes": {"usesNonExemptEncryption": False}}})
            print("  set usesNonExemptEncryption=false ->", err or "ok")
            if err: sys.exit(24)
    # --- attach ---
    if str(cur_v) != str(BUILD_NUMBER):
        print(f"  PLAN: attach build {BUILD_NUMBER} (replacing {cur_v})")
        if write:
            _, err = call("PATCH", f"/v1/appStoreVersions/{ver['id']}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
            print("  attach build ->", err or "ok")
            if err: print("  STOP: API refused the build change"); sys.exit(25)
    else:
        print("  attach: already attached, no change")

    # --- review notes ---
    rd = get(f"/v1/appStoreVersions/{ver['id']}/appStoreReviewDetail")
    rdd = (rd or {}).get("data")
    if not rdd: print("  STOP: appStoreReviewDetail missing"); sys.exit(26)
    notes = rdd["attributes"].get("notes") or ""
    print(f"  notes: len={len(notes)} old92Line={OLD_LINE in notes} new94Line={NEW_LINE in notes}")
    if NEW_LINE in notes and OLD_LINE not in notes:
        print("  notes: already updated, no change")
    else:
        if OLD_LINE in notes:
            new = notes.replace(OLD_LINE, NEW_LINE)
        elif NEW_LINE in notes:
            new = notes
        else:
            new = notes.rstrip() + "\n\n" + NEW_LINE
        print(f"  PLAN: notes {len(notes)} -> {len(new)} chars")
        if len(new) > 4000: print("  STOP: notes would exceed 4000 chars"); sys.exit(27)
        if write:
            _, err = call("PATCH", f"/v1/appStoreReviewDetails/{rdd['id']}", {"data": {"type": "appStoreReviewDetails", "id": rdd["id"], "attributes": {"notes": new}}})
            print("  update notes ->", err or "ok")
            if err: sys.exit(28)

    # --- readback (read-only) ---
    time.sleep(5 if write else 0)
    b2 = get(f"/v1/appStoreVersions/{ver['id']}/build")
    print("  READBACK attached build:", (((b2 or {}).get("data") or {}).get("attributes") or {}).get("version"))
    bb = get(f"/v1/builds/{build['id']}")
    print("  READBACK build nonExemptEnc:", bb and bb["data"]["attributes"].get("usesNonExemptEncryption"))
    rd2 = get(f"/v1/appStoreReviewDetails/{rdd['id']}")
    n2 = ((rd2 or {}).get("data", {}).get("attributes", {}).get("notes") or "")
    print(f"  READBACK notes: len={len(n2)} old92Line={OLD_LINE in n2} new94Line={NEW_LINE in n2}")
    r2 = get(f"/v1/reviewSubmissions/{RS_ID}")
    print("  READBACK submission state:", r2 and r2["data"]["attributes"].get("state"))
    it = get(f"/v1/reviewSubmissions/{RS_ID}/items", {"limit": 50})
    print("  READBACK items states:", [x["attributes"].get("state") for x in (it or {}).get("data", [])])
    v2 = get(f"/v1/appStoreVersions/{ver['id']}")
    print("  READBACK version state:", v2 and v2["data"]["attributes"].get("appStoreState"))
    # --- Terms of Use link in every 1.6.1 description (read-only) ---
    EULA_URL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    locs = get(f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations", {"limit": 50})
    for loc in (locs or {}).get("data", []):
        print(f"  READBACK [{loc['attributes']['locale']}] Terms of Use link in description: {EULA_URL in (loc['attributes'].get('description') or '')}")
    import base64
    def kind(i):
        try: return base64.urlsafe_b64decode(i + "=" * (-len(i) % 4)).decode().split("|")[1]
        except Exception: return "?"
    print("  READBACK items (kind 6=version, 18=subscription, 19=group):",
          [(kind(x["id"]), x["attributes"].get("state")) for x in (it or {}).get("data", [])])
