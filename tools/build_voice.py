#!/usr/bin/env python3
"""Build the Godslayer announcer from tools/voice_script.json.

    python3 tools/build_voice.py [--pack titan] [--only first_blood,godlike] [--redo]

with your ElevenLabs key in the environment variable named ELEVENLABS_API_KEY.

For every line and every pack it asks the voice service for a take, has the same service
transcribe the take back, and keeps it only if the words match; a bad take is retried. The kept
take is then given the arena treatment with ffmpeg (deeper, compressed, a hall behind it, and
for the kill calls an impact hit underneath) and written to Godslayer/Sounds/<pack>/<clip>.ogg.
Godslayer/Voice.lua, the list of clips and their lengths the addon reads, is rewritten at the end.
Raw takes are cached in tools/.voice_cache so a rerun only pays for what changed.
Needs ffmpeg and ffprobe. The service is ElevenLabs; the voices are its stock ones.
"""
import difflib
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, ".voice_cache")
OUT = os.path.join(ROOT, "Godslayer", "Sounds")
API = "https://api.elevenlabs.io/v1"
KEY = os.environ.get("ELEVENLABS_API_KEY", "")
ATTEMPTS = 4
GOOD_ENOUGH = 0.86

# how each kind of line is asked for: the tag steers the delivery, the settings how wild the take may be
DELIVERY = {
    "call": {"tag": "[shouting] ", "stability": 0.0},
    "points": {"tag": "[shouting] ", "stability": 0.5},
    "title": {"tag": "[proud, slow] ", "stability": 0.5},
    "aside": {"tag": "[deadpan] ", "stability": 0.5},
}
HALLS = {
    # delays in ms | decays: left and right differ so the tail spreads
    "big": ("43|97|167|251|349|463", "0.34|0.28|0.22|0.16|0.11|0.07", "53|113|181|277|373|491", "0.33|0.27|0.21|0.15|0.10|0.06"),
    "tight": ("31|71|113|173", "0.30|0.20|0.12|0.07", "37|79|127|191", "0.29|0.19|0.11|0.06"),
}
LOUDNESS = {"call": -9.5, "points": -10.5, "title": -11.5, "aside": -13.0}


def post(path, payload=None, form=None):
    headers = {"xi-api-key": KEY}
    if form is not None:
        boundary = "----godslayer" + hashlib.md5(os.urandom(8)).hexdigest()
        body = b""
        for name, value in form.items():
            body += ("--%s\r\n" % boundary).encode()
            if isinstance(value, tuple):
                body += ('Content-Disposition: form-data; name="%s"; filename="%s"\r\nContent-Type: application/octet-stream\r\n\r\n' % (name, value[0])).encode() + value[1] + b"\r\n"
            else:
                body += ('Content-Disposition: form-data; name="%s"\r\n\r\n%s\r\n' % (name, value)).encode()
        body += ("--%s--\r\n" % boundary).encode()
        headers["Content-Type"] = "multipart/form-data; boundary=" + boundary
    else:
        body = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(API + path, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def words(text):
    return re.sub(r"[^a-z0-9 ]", "", re.sub(r"\[[^\]]*\]", "", text).lower().replace("'", "")).split()


def match(expected, heard):
    a, b = " ".join(words(expected)), " ".join(words(heard))
    return difflib.SequenceMatcher(None, a, b).ratio()


def take(pack, clip, kind, text, attempt):
    """One raw take, from the cache when there is one. Returns (path, what it was heard to say, score)."""
    folder = os.path.join(CACHE, pack["id"])
    os.makedirs(folder, exist_ok=True)
    # the clip name is part of the stamp so two takes of the same words are two different takes
    stamp = hashlib.md5(("%s|%s|%s|%s|%s" % (pack["voice"], kind, text, attempt, clip)).encode()).hexdigest()[:10]
    variant = int(hashlib.md5(clip.encode()).hexdigest()[:6], 16) % 100000
    audio, note = os.path.join(folder, "%s.%s.mp3" % (clip, stamp)), os.path.join(folder, "%s.%s.json" % (clip, stamp))
    if not os.path.exists(audio):
        style = DELIVERY[kind]
        data = post("/text-to-speech/%s?output_format=mp3_44100_128" % pack["voice"], {
            "text": style["tag"] + text, "model_id": "eleven_v3", "seed": 1000 + variant + attempt * 7919,
            "voice_settings": {"stability": style["stability"], "similarity_boost": 0.8, "use_speaker_boost": True}})
        with open(audio, "wb") as f:
            f.write(data)
    if not os.path.exists(note):
        with open(audio, "rb") as f:
            heard = json.loads(post("/speech-to-text", form={"model_id": "scribe_v1", "language_code": "en", "file": ("take.mp3", f.read())})).get("text", "")
        with open(note, "w") as f:
            json.dump({"heard": heard}, f)
    heard = json.load(open(note))["heard"]
    return audio, heard, match(text, heard)


def impact():
    """The hit under every kill call: asked for once, then kept."""
    path = os.path.join(CACHE, "impact.mp3")
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        with open(path, "wb") as f:
            f.write(post("/sound-generation", {"text": "single deep cinematic sub bass impact boom, dark, short reverb tail, no music, no voice",
                                               "duration_seconds": 1.6, "prompt_influence": 0.7}))
    return path


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path], capture_output=True, text=True).stdout
    return float(out.strip() or 0)


def treat(raw, dst, kind, pack, stutter=False):
    """Trim, deepen, shape, put a hall behind it, and for a call put the impact under the first word."""
    left_d, left_g, right_d, right_g = HALLS[pack["hall"]]
    wet = 0.55 if kind == "call" else (0.4 if kind in ("points", "title") else 0.22)
    voice = ("silenceremove=start_periods=1:start_threshold=-42dB:start_silence=0.02,areverse,"
             "silenceremove=start_periods=1:start_threshold=-42dB:start_silence=0.06,areverse,"
             "asetrate=44100*%.4f,aresample=44100,atempo=%.4f,"
             "highpass=f=70,bass=g=4:f=130:w=0.7,equalizer=f=2800:t=q:w=1.2:g=3,equalizer=f=420:t=q:w=1.4:g=-2,"
             "acompressor=threshold=-24dB:ratio=5:attack=4:release=90:makeup=5,volume=5dB,asoftclip=type=tanh,apad=pad_dur=0.55"
             % (pack["pitch"], pack["speed"] / pack["pitch"]))
    graph = ("[0:a]%s,asplit=4[d1][d2][l0][r0];"
             "[l0]aecho=0.9:%.2f:%s:%s,lowpass=f=5200[lw];[r0]aecho=0.9:%.2f:%s:%s,lowpass=f=5200[rw];"
             "[d1][lw]amix=inputs=2:weights='1 0.6':normalize=0[L];[d2][rw]amix=inputs=2:weights='1 0.6':normalize=0[R];"
             "[L][R]join=inputs=2:channel_layout=stereo[v]" % (voice, wet, left_d, left_g, wet, right_d, right_g))
    if stutter:
        # the first tenth of a second three times before the word itself: G-G-G-GODSLAYER
        head = "atrim=0:0.11,asetpts=N/SR/TB,afade=t=out:st=0.08:d=0.03,apad=pad_dur=0.05"
        graph = ("[0:a]silenceremove=start_periods=1:start_threshold=-42dB:start_silence=0.02,asplit=4[h1][h2][h3][body];"
                 "[h1]%s[a1];[h2]%s[a2];[h3]%s[a3];[a1][a2][a3][body]concat=n=4:v=0:a=1[st];" % (head, head, head)) + graph.replace("[0:a]", "[st]", 1)
    inputs = ["-i", raw]
    if kind == "call":
        inputs += ["-i", impact()]
        graph += (";[1:a]aformat=channel_layouts=stereo,lowpass=f=900,volume=-7dB,afade=t=out:st=0.9:d=0.6[hit];"
                  "[v][hit]amix=inputs=2:duration=first:normalize=0[m]")
        last = "[m]"
    else:
        last = "[v]"
    graph += ";%sloudnorm=I=%.1f:TP=-1.0:LRA=6[o]" % (last, LOUDNESS[kind])
    # the closing fade is applied below, once the length is known
    tmp = dst + ".tmp.wav"
    subprocess.run(["ffmpeg", "-v", "warning", "-y"] + inputs + ["-filter_complex", graph, "-map", "[o]", "-ar", "44100", tmp], check=True)
    length = duration(tmp)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-af", "afade=t=out:st=%.3f:d=0.12" % max(0, length - 0.12),
                    "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
    os.remove(tmp)
    return duration(dst)


def main():
    if not KEY:
        sys.exit("Set ELEVENLABS_API_KEY.")
    args = sys.argv[1:]
    only_pack = args[args.index("--pack") + 1] if "--pack" in args else None
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else None
    script = json.load(open(os.path.join(HERE, "voice_script.json")))
    lengths, report = {}, []
    for pack_id, pack in script["packs"].items():
        pack["id"] = pack_id
        lengths[pack_id] = {}
        folder = os.path.join(OUT, pack_id)
        os.makedirs(folder, exist_ok=True)
        for clip, kind, text in script["clips"]:
            dst = os.path.join(folder, clip + ".ogg")
            skip = (only_pack and pack_id != only_pack) or (only and clip not in only)
            if skip or (os.path.exists(dst) and "--redo" not in args and not only):
                if os.path.exists(dst):
                    lengths[pack_id][clip] = duration(dst)
                continue
            best = None
            for attempt in range(ATTEMPTS):
                raw, heard, score = take(pack, clip, kind, text, attempt)
                if best is None or score > best[2]:
                    best = (raw, heard, score)
                if score >= GOOD_ENOUGH:
                    break
            lengths[pack_id][clip] = treat(best[0], dst, kind, pack, stutter=clip in script.get("stutter", []))
            flag = "" if best[2] >= GOOD_ENOUGH else "   <-- CHECK THIS ONE"
            report.append("%-7s %-18s %.2f  %4.1fs  heard: %s%s" % (pack_id, clip, best[2], lengths[pack_id][clip], best[1].strip(), flag))
            print(report[-1], flush=True)

    lines = ["-- Written by tools/build_voice.py from tools/voice_script.json. Do not edit by hand.",
             "-- Each pack: its name in the options, and every clip with its length in seconds.", "local _, ns = ...", "", "ns.VOICE = {"]
    for pack_id, pack in script["packs"].items():
        lines.append('  %s = { label = "%s", about = "%s", clips = {' % (pack_id, pack["label"], pack["about"]))
        for clip, _, _ in script["clips"]:
            if clip in lengths[pack_id]:
                lines.append("    %s = %.2f," % (clip, lengths[pack_id][clip]))
        lines.append("  } },")
    lines += ["}", "", "-- what each clip says, for the options window and for anyone reading along", "ns.VOICE_TEXT = {"]
    for clip, _, text in script["clips"]:
        lines.append('  %s = "%s",' % (clip, text.replace('"', '\\"')))
    lines += ["}", ""]
    with open(os.path.join(ROOT, "Godslayer", "Voice.lua"), "w") as f:
        f.write("\n".join(lines))
    bad = [r for r in report if "CHECK" in r]
    print("\n%d clips built, %d need a listen." % (len(report), len(bad)))


if __name__ == "__main__":
    main()
