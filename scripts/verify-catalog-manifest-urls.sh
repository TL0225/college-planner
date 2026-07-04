#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/College/Features/Catalog/schools.json"

if [[ ! -f "${MANIFEST}" ]]; then
  echo "Missing manifest: ${MANIFEST}" >&2
  exit 1
fi

tmp="$(mktemp)"
python3 - <<'PY' "${MANIFEST}" > "${tmp}"
import json,sys,urllib.request,urllib.error,re
manifest_path=sys.argv[1]
schools=json.load(open(manifest_path,"r",encoding="utf-8"))

def detect(url:str)->str:
    req=urllib.request.Request(url,headers={"User-Agent":"Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req,timeout=20) as r:
            final=r.geturl()
            ctype=(r.headers.get("Content-Type") or "").lower()
            body=r.read(262144).decode("utf-8","ignore").lower()
    except Exception:
        return "unknown"
    if "application/pdf" in ctype or final.lower().endswith(".pdf"):
        return "pdf"
    if body.count("coursedog") >= 3:
        return "coursedog"
    if "courseleaf.css" in body or "sc_courselist" in body:
        return "courseleaf"
    if "catalog_list.php" in body or "catoid=" in body or "id=\"acalog-content\"" in body:
        return "acalog"
    if "wp-json" in body:
        return "custom"
    return "unknown"

def normalize(fmt:str)->str:
    f=(fmt or "").strip().lower()
    if f=="moderncampus": return "acalog"
    return f

failures=[]
for school in schools:
    sid=school.get("id","")
    url=(school.get("catalog_url") or "").strip()
    declared=normalize(school.get("catalog_format",""))
    if not url:
        failures.append((sid,declared,"missing_url",url))
        continue
    detected=normalize(detect(url))
    if detected!="unknown" and declared and declared!=detected:
        failures.append((sid,declared,detected,url))

if failures:
    print("Catalog manifest verification failed:")
    for sid,declared,detected,url in failures:
        print(f"- {sid}: declared={declared} detected={detected} url={url}")
    sys.exit(2)
print("Catalog manifest verification passed.")
PY

cat "${tmp}"
rm -f "${tmp}"
