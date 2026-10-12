#!/usr/bin/env python3
"""Upload a release zip to CurseForge.

    python3 tools/curseforge_upload.py <project id> <zip> <notes.md> [--dry]

The upload key is read from the environment variable CURSEFORGE_UPLOAD_KEY. The game version is
looked up from the Interface number in the toc inside the zip, so a file is never filed under a
version CurseForge does not list.
"""
import json
import os
import re
import sys
import urllib.request
import zipfile

API = "https://wow.curseforge.com/api"
KEY = os.environ.get("CURSEFORGE_UPLOAD_KEY", "")


def get(path):
    request = urllib.request.Request(API + path, headers={"X-Api-Token": KEY, "User-Agent": "godslayer-release"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read())


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 3:
        sys.exit(__doc__)
    if not KEY:
        sys.exit("CURSEFORGE_UPLOAD_KEY is not set.")
    project, path, notes = args
    with zipfile.ZipFile(path) as z:
        toc = next(n for n in z.namelist() if n.endswith(".toc"))
        text = z.read(toc).decode("utf-8", "replace")
    interface = re.search(r"^## Interface:\s*(\d+)", text, re.M).group(1)
    version = re.search(r"^## Version:\s*(\S+)", text, re.M).group(1)
    matches = [v for v in get("/game/versions") if str(v.get("apiVersion", "")).strip() == interface]
    if not matches:
        sys.exit("CurseForge lists no game version for Interface %s." % interface)
    meta = {"changelog": open(notes).read(), "changelogType": "markdown", "displayName": "Godslayer " + version,
            "gameVersions": [v["id"] for v in matches], "releaseType": "release"}
    print("project %s, %s, game version %s" % (project, meta["displayName"], ", ".join(v["name"] for v in matches)))
    if "--dry" in sys.argv:
        return
    boundary = "----godslayer" + os.urandom(8).hex()
    body = ("--%s\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n%s\r\n" % (boundary, json.dumps(meta))).encode()
    body += ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\nContent-Type: application/zip\r\n\r\n"
             % (boundary, os.path.basename(path))).encode() + open(path, "rb").read() + ("\r\n--%s--\r\n" % boundary).encode()
    request = urllib.request.Request("%s/projects/%s/upload-file" % (API, project), data=body, method="POST", headers={
        "X-Api-Token": KEY, "User-Agent": "godslayer-release", "Content-Type": "multipart/form-data; boundary=" + boundary})
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            print("uploaded, file id", json.loads(response.read()).get("id"))
    except urllib.error.HTTPError as e:
        sys.exit("CurseForge said %s: %s" % (e.code, e.read().decode("utf-8", "replace")[:400]))


if __name__ == "__main__":
    main()
