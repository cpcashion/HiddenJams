"""Read-only subscription diagnostics (imported by asc_submit.py when MODE=diag). Prints no secrets/PII."""
import datetime

def run(get, APP_ID, SUB_ID):
    today = datetime.date.today().isoformat()
    for sid in (SUB_ID, "6821011508"):
        print(f"\n######## subscription {sid}")
        s = get(f"/v1/subscriptions/{sid}")
        if not s: continue
        a = s["data"]["attributes"]
        print("  attrs:", {k: a.get(k) for k in ("productId", "name", "state", "subscriptionPeriod", "groupLevel", "familySharable", "availableInAllTerritories")})
        # prices
        pr = get(f"/v1/subscriptions/{sid}/prices", {"include": "territory,subscriptionPricePoint", "limit": 200})
        inc = {(i["type"], i["id"]): i for i in (pr or {}).get("included", [])}
        rows = []
        for p in (pr or {}).get("data", []):
            t = p["relationships"]["territory"]["data"]["id"]
            pp = (p["relationships"].get("subscriptionPricePoint") or {}).get("data")
            ppa = inc.get(("subscriptionPricePoints", pp["id"]), {}).get("attributes", {}) if pp else {}
            rows.append((t, p["attributes"].get("startDate"), p["attributes"].get("preserved"), ppa.get("customerPrice"), pp and pp["id"]))
        cur = [r for r in rows if not r[1] or r[1] <= today]
        fut = [r for r in rows if r[1] and r[1] > today]
        print(f"  prices total={len(rows)} current(start null/past)={len(cur)} future={len(fut)}")
        for r in rows:
            if r[0] in ("USA", "CAN"): print(f"    {r[0]} start={r[1]} preserved={r[2]} customerPrice={r[3]} pricePoint={r[4]}")
        if fut[:3]: print("    sample future:", fut[:3])
        # availability
        av = get(f"/v1/subscriptions/{sid}/subscriptionAvailability")
        if av and av.get("data"):
            at = get(f"/v1/subscriptionAvailabilities/{av['data']['id']}/availableTerritories", {"limit": 200})
            print(f"  availability id={av['data']['id']} newTerritories={av['data']['attributes'].get('availableInNewTerritories')} territories={[x['id'] for x in (at or {}).get('data', [])]}")
        else:
            print("  availability: none")
        # review screenshot (legacy path)
        rs = get(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
        d = rs.get("data") if rs else None
        if d:
            ra = d["attributes"]
            print(f"  reviewScreenshot id={d['id']} file={ra.get('fileName')} size={ra.get('fileSize')} checksum={'set' if ra.get('sourceFileChecksum') else 'none'} imageAsset={'set' if ra.get('imageAsset') else 'none'} delivery={ra.get('assetDeliveryState')}")
        else:
            print("  reviewScreenshot: none")
        # newer subscriptionVersions model (API 4.4.1+), if present
        for path in (f"/v1/subscriptions/{sid}/subscriptionVersions", f"/v1/subscriptions/{sid}/versions"):
            v = get(path, {"limit": 10})
            if v is not None:
                for x in v.get("data", []):
                    print(f"  {path.split('/')[-1]}: id={x['id']} attrs={x.get('attributes')}")
                    for rel in ("appStoreReviewScreenshot", "subscriptionLocalizations", "subscriptionImages"):
                        r = get(f"/v1/subscriptionVersions/{x['id']}/{rel}")
                        if r is not None:
                            dd = r.get("data")
                            n = len(dd) if isinstance(dd, list) else (1 if dd else 0)
                            print(f"     {rel}: {n}" + (f" delivery={(dd.get('attributes') or {}).get('assetDeliveryState')}" if isinstance(dd, dict) and dd else ""))
                break
        locs = get(f"/v1/subscriptions/{sid}/subscriptionLocalizations")
        print(f"  legacy localizations: {[(l['attributes'].get('locale'), l['attributes'].get('state')) for l in (locs or {}).get('data', [])]}")
    print("\nDIAG done (read-only)")

def review(get, APP_ID, SUB_ID, RS_ID="07b5db50-fcf3-42d6-9cad-8c6a49bf9548"):
    """Read-only App Review state dump. Prints states/ids only (no secrets/PII)."""
    def show(label, path, params=None):
        d = get(path, params)
        print(f"\n## {label}: GET {path} {params or ''} -> {'ok' if d is not None else 'ERROR/404 (see above)'}")
        return d
    d = show("reviewSubmission", f"/v1/reviewSubmissions/{RS_ID}", {"include": "items,appStoreVersionForReview"})
    if d:
        a = d["data"]["attributes"]
        print("  attrs:", a)
        print("  relationships:", {k: (v.get("data") if isinstance(v, dict) else v) for k, v in d["data"].get("relationships", {}).items() if isinstance(v, dict) and "data" in v})
    it = show("items", f"/v1/reviewSubmissions/{RS_ID}/items", {"include": "appStoreVersion", "limit": 50})
    for x in (it or {}).get("data", []):
        rel = {k: v.get("data") for k, v in x.get("relationships", {}).items() if isinstance(v, dict) and v.get("data")}
        print(f"  item {x['id']} attrs={x.get('attributes')} rel={rel}")
    rs = show("app reviewSubmissions", f"/v1/apps/{APP_ID}/reviewSubmissions", {"filter[platform]": "IOS", "limit": 5})
    for r in (rs or {}).get("data", []):
        print(f"  {r['id']} {r['attributes']}")
    vs = show("versions", f"/v1/apps/{APP_ID}/appStoreVersions", {"filter[platform]": "IOS", "limit": 5})
    for v in (vs or {}).get("data", []):
        va = v["attributes"]
        print(f"  {v['id']} {va.get('versionString')} appStoreState={va.get('appStoreState')} appVersionState={va.get('appVersionState')} reviewType={va.get('reviewType')}")
        if va.get("versionString") == "1.6.1":
            show("appStoreVersionSubmission", f"/v1/appStoreVersions/{v['id']}/appStoreVersionSubmission")
            b = show("build", f"/v1/appStoreVersions/{v['id']}/build")
            if b and b.get("data"): print("  build", b["data"]["attributes"].get("version"), b["data"]["attributes"].get("processingState"))
            for p in (f"/v1/appStoreVersions/{v['id']}/reviewRejections", f"/v1/appStoreVersions/{v['id']}/resolutionCenterThreads"):
                show("probe", p)
    s = show("subscription", f"/v1/subscriptions/{SUB_ID}")
    if s: print("  state:", s["data"]["attributes"].get("state"))
    sv = show("subscription versions", f"/v1/subscriptions/{SUB_ID}/versions", {"limit": 5})
    for x in (sv or {}).get("data", []): print("  ", x["id"], x.get("attributes"))
    sg = show("groups", f"/v1/apps/{APP_ID}/subscriptionGroups", {"limit": 10})
    for g in (sg or {}).get("data", []):
        print(f"  group {g['id']} attrs={g.get('attributes')}")
        for p in (f"/v1/subscriptionGroups/{g['id']}/subscriptionGroupSubmissions", f"/v1/subscriptionGroups/{g['id']}/subscriptionGroupLocalizations"):
            gg = show("group probe", p)
            for x in (gg or {}).get("data", []): print("   ", x["id"], {k: x["attributes"].get(k) for k in ("locale", "state")})
    for p, prm in ((f"/v1/reviewSubmissions/{RS_ID}/resolutionCenterThreads", None),
                   ("/v1/resolutionCenterThreads", {"filter[reviewSubmission]": RS_ID}),
                   ("/v1/reviewRejections", {"filter[reviewSubmission]": RS_ID}),
                   (f"/v1/apps/{APP_ID}/resolutionCenterThreads", None)):
        show("rejection-text probe", p, prm)
    print("\nREVIEW DIAG done (read-only)")
