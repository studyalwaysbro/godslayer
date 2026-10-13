#!/usr/bin/env python3
"""Build the Godslayer announcers, sound effects and hunt theme from tools/voice_script.json.

    python3 tools/build_voice.py [--pack frost] [--only first_blood_1,godlike] [--redo] [--jobs 3]

with your ElevenLabs key in the environment variable named ELEVENLABS_API_KEY.

Every pack is a voice reading one of the scripts. For every line the voice service is asked for
a take, and the same service transcribes the take back; a take whose words are wrong is thrown
away. A kill call gets several good takes and the best one is kept: the fiercest for a shouting
announcer, the most even for a calm one. The kept take is given the arena treatment with ffmpeg
(pitched, compressed, a hall behind it, and for the kill calls the pack's own impact hit
underneath) and written to Godslayer/Sounds/<pack>/<clip>.ogg.

Then every finished clip is measured (length against the words in it, silence inside it) and the
ones that look wrong are taken again. tools/voice_report.md lists what was kept and what is
still worth a listen, and tools/audition.html is a page with a button for every clip.

Godslayer/Voice.lua, the list of packs, clips and lengths the addon reads, is rewritten at the
end. Raw takes are cached in tools/.voice_cache so a rerun only pays for what changed.
Needs ffmpeg and ffprobe. The service is ElevenLabs; the voices are its stock ones.
"""
import concurrent.futures
import difflib
import hashlib
import html
import json
import os
import re
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, ".voice_cache")
OUT = os.path.join(ROOT, "Godslayer", "Sounds")
API = "https://api.elevenlabs.io/v1"
KEY = os.environ.get("ELEVENLABS_API_KEY", "")
ATTEMPTS = 6          # the most takes one line may cost
CALL_TAKES = 3        # good takes wanted for a kill call before the best is chosen
GOOD_ENOUGH = 0.86
TREATMENT = 3         # raise when the ffmpeg chain changes, so every clip is made again from its kept take
MAX_PAUSE = 1.6       # a take with a longer silence inside it has lost its thread
LEGACY_HIT = "single deep cinematic sub bass impact boom, dark, short reverb tail, no music, no voice"

# how each kind of line is asked for, unless the pack says otherwise: the tag steers the
# delivery, the setting says how wild the take may be
DELIVERY = {
    "call": {"tag": "[shouting] ", "stability": 0.0},
    "points": {"tag": "[shouting] ", "stability": 0.5},
    "title": {"tag": "[proud, slow] ", "stability": 0.5},
    "aside": {"tag": "[deadpan] ", "stability": 0.5},
}
HALLS = {
    # delays in ms | decays: left and right differ so the tail spreads | how much of it
    "big": ("43|97|167|251|349|463", "0.34|0.28|0.22|0.16|0.11|0.07", "53|113|181|277|373|491", "0.33|0.27|0.21|0.15|0.10|0.06", 1.0),
    "tight": ("31|71|113|173", "0.30|0.20|0.12|0.07", "37|79|127|191", "0.29|0.19|0.11|0.06", 1.0),
    "dry": ("23|47", "0.16|0.07", "29|53", "0.15|0.06", 0.45),
}
LOUDNESS = {"call": -9.5, "points": -10.5, "title": -11.5, "aside": -13.0}
slow = threading.Semaphore(3)
print_lock = threading.Lock()


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
    for wait in (2, 5, 12, 30, None):
        request = urllib.request.Request(API + path, data=body, headers=headers, method="POST")
        try:
            with slow, urllib.request.urlopen(request, timeout=300) as response:
                return response.read()
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf8", "replace")[:300]
            if e.code in (429, 500, 502, 503, 504) and wait and "quota" not in detail:
                time.sleep(wait)
                continue
            raise RuntimeError("%s said %s: %s" % (path.split("?")[0], e.code, detail))
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if not wait:
                raise
            time.sleep(wait)


def spoken(text):
    """The words of a line without the delivery notes in square brackets."""
    return re.sub(r"\s+", " ", re.sub(r"\[[^\]]*\]", "", text)).strip()


NUMBERS = {"20": "twenty", "25": "twenty five", "30": "thirty", "40": "forty", "50": "fifty", "1": "one", "5": "five"}


def words(text):
    # the transcription writes numbers as digits; the script spells them
    plain = re.sub(r"[^a-z0-9 ]", "", spoken(text).lower().replace("'", "").replace("-", " "))
    return " ".join(NUMBERS.get(word, word) for word in plain.split()).split()


def match(expected, heard):
    a, b = " ".join(words(expected)), " ".join(words(heard))
    return difflib.SequenceMatcher(None, a, b).ratio()


def expected_seconds(text):
    return 0.5 + 0.42 * len(words(text))


def probe(path, entry="format=duration"):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", entry, "-of", "csv=p=0", path], capture_output=True, text=True).stdout
    return float(out.strip() or 0)


def mean_volume(path, filters=""):
    err = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-af", filters + "volumedetect", "-f", "null", "-"], capture_output=True, text=True).stderr
    found = re.search(r"mean_volume: (-?[\d.]+) dB", err)
    return float(found.group(1)) if found else -90.0


def speech_seconds(path):
    """How long the speaking itself is, without the quiet at either end."""
    err = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-af", "silencedetect=noise=-40dB:d=0.05", "-f", "null", "-"], capture_output=True, text=True).stderr
    total = probe(path)
    starts = [float(x) for x in re.findall(r"silence_start: (-?[\d.]+)", err)]
    ends = [float(x) for x in re.findall(r"silence_end: (-?[\d.]+)", err)]
    begin = ends[0] if starts and starts[0] <= 0.05 and ends else 0.0
    finish = starts[-1] if starts and len(starts) > len(ends) else total
    gaps = [e - s for s, e in zip(starts, ends) if s > begin + 0.01 and e < finish - 0.01]
    return max(0.0, finish - begin), (max(gaps) if gaps else 0.0)


def take(pack, clip, kind, text, attempt):
    """One raw take, from the cache when there is one. Returns a dict describing it."""
    folder = os.path.join(CACHE, pack["id"])
    os.makedirs(folder, exist_ok=True)
    style = pack.get("delivery", {}).get(kind) or DELIVERY[kind]
    # the clip name is part of the stamp so two takes of the same words are two different takes
    stamp = hashlib.md5(("%s|%s|%s|%s|%s" % (pack["voice"], kind, text, attempt, clip)).encode()).hexdigest()[:10]
    if style != DELIVERY[kind]:
        stamp = hashlib.md5((stamp + json.dumps(style, sort_keys=True)).encode()).hexdigest()[:10]
    variant = int(hashlib.md5(clip.encode()).hexdigest()[:6], 16) % 100000
    audio, note = os.path.join(folder, "%s.%s.mp3" % (clip, stamp)), os.path.join(folder, "%s.%s.json" % (clip, stamp))
    if not os.path.exists(audio):
        data = post("/text-to-speech/%s?output_format=mp3_44100_128" % pack["voice"], {
            "text": style["tag"] + text, "model_id": "eleven_v3", "seed": 1000 + variant + attempt * 7919,
            "voice_settings": {"stability": style["stability"], "similarity_boost": 0.8, "use_speaker_boost": True}})
        with open(audio + ".part", "wb") as f:
            f.write(data)
        os.replace(audio + ".part", audio)
    info = json.load(open(note)) if os.path.exists(note) else {}
    if "heard" not in info:
        with open(audio, "rb") as f:
            info["heard"] = json.loads(post("/speech-to-text", form={"model_id": "scribe_v1", "language_code": "en", "file": ("take.mp3", f.read())})).get("text", "")
    if "speech" not in info:
        info["speech"], info["gap"] = speech_seconds(audio)
        full = mean_volume(audio)
        info["level"], info["bite"] = full, mean_volume(audio, "highpass=f=2200,") - full
        with open(note, "w") as f:
            json.dump(info, f)
    info.update(path=audio, attempt=attempt, score=match(text, info["heard"]))
    # a take that runs far past its words has something extra in it: a laugh, a breath, a second go
    info["long"] = info["speech"] > max(2.4, expected_seconds(text) * 1.9) + 0.5 * text.count(". ") + 0.5 * text.count("! ")
    info["good"] = info["score"] >= GOOD_ENOUGH and not info["long"] and info["gap"] < MAX_PAUSE
    return info


def choose(pack, clip, kind, text, skip=()):
    """Takes until there are enough good ones, then the best of them."""
    wanted = CALL_TAKES if kind == "call" else 1
    takes = []
    for attempt in range(ATTEMPTS):
        if attempt in skip:
            continue
        takes.append(take(pack, clip, kind, text, attempt))
        if sum(1 for t in takes if t["good"]) >= wanted:
            break
    good = [t for t in takes if t["good"]]
    if not good:
        return max(takes, key=lambda t: (t["score"], -t["speech"])), takes
    if kind != "call" or len(good) == 1:
        return good[0], takes
    if pack.get("calm"):
        middle = statistics.median(t["speech"] for t in good)
        return min(good, key=lambda t: abs(t["speech"] - middle)), takes
    # the fiercest: the most edge in the voice, the loudest, and no dawdling
    return max(good, key=lambda t: t["bite"] + 0.3 * t["level"] - 2.5 * max(0.0, t["speech"] - expected_seconds(text))), takes


def generated(name, prompt, seconds):
    """A sound asked for once from the sound-effects service, then kept."""
    legacy = os.path.join(CACHE, "impact.mp3")
    if prompt == LEGACY_HIT and os.path.exists(legacy):
        return legacy
    path = os.path.join(CACHE, "%s_%s.mp3" % (name, hashlib.md5(("%s|%s" % (prompt, seconds)).encode()).hexdigest()[:8]))
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        data = post("/sound-generation", {"text": prompt, "duration_seconds": seconds, "prompt_influence": 0.7})
        with open(path, "wb") as f:
            f.write(data)
    return path


def treat(raw, dst, kind, pack, stutter=False):
    """Trim, pitch, shape, put a hall behind it, and for a call put the impact under the first word."""
    left_d, left_g, right_d, right_g, amount = HALLS[pack["hall"]]
    wet = (0.55 if kind == "call" else (0.4 if kind in ("points", "title") else 0.22)) * amount
    voice = ("silenceremove=start_periods=1:start_threshold=-42dB:start_silence=0.02,areverse,"
             "silenceremove=start_periods=1:start_threshold=-42dB:start_silence=0.06,areverse,"
             # a pause between two sentences is kept to a third of a second: these are heard mid-fight
             "silenceremove=stop_periods=-1:stop_duration=0.45:stop_threshold=-38dB:stop_silence=0.33,"
             "asetrate=44100*%.4f,aresample=44100,atempo=%.4f,"
             "highpass=f=70,bass=g=%d:f=130:w=0.7,equalizer=f=2800:t=q:w=1.2:g=3,equalizer=f=420:t=q:w=1.4:g=-2,"
             "acompressor=threshold=-24dB:ratio=5:attack=4:release=90:makeup=5,volume=5dB,asoftclip=type=tanh,apad=pad_dur=0.55"
             % (pack["pitch"], pack["speed"] / pack["pitch"], pack.get("bass", 4)))
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
    if kind == "call" and pack.get("hit"):
        inputs += ["-i", generated("hit", pack["hit"], 1.6)]
        graph += (";[1:a]aformat=channel_layouts=stereo,lowpass=f=%d,volume=%.1fdB,afade=t=out:st=0.9:d=0.6[hit];"
                  "[v][hit]amix=inputs=2:duration=first:normalize=0[m]" % (pack.get("hit_lowpass", 900), pack.get("hit_db", -7)))
        last = "[m]"
    else:
        last = "[v]"
    graph += ";%sloudnorm=I=%.1f:TP=-1.0:LRA=6[o]" % (last, LOUDNESS[kind] + pack.get("gain", 0))
    # the closing fade is applied below, once the length is known
    tmp = dst + ".tmp.wav"
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", graph, "-map", "[o]", "-ar", "44100", tmp], check=True)
    length = probe(tmp)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-af", "afade=t=out:st=%.3f:d=0.12" % max(0, length - 0.12),
                    "-c:a", "libvorbis", "-q:a", "2", dst], check=True)
    os.remove(tmp)
    return probe(dst)


def finish(raw, dst, loudness, quality=4, fade_in=0.01, fade_out=0.25, trim=True):
    """A generated sound or piece of music: trimmed, levelled, with clean edges."""
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    cut = ("silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.02,areverse,"
           "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05,areverse,") if trim else ""
    tmp = dst + ".tmp.wav"
    # a sound the trim cannot make sense of must fail, not hang the build
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af", cut + "aformat=channel_layouts=stereo,loudnorm=I=%.1f:TP=-1.5:LRA=9" % loudness, "-ar", "44100", tmp], check=True, timeout=120)
    if probe(tmp) < 0.15:
        os.remove(tmp)
        raise RuntimeError("nothing left after trimming: the sound came back silent")
    length = probe(tmp)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-af", "afade=t=in:st=0:d=%.3f,afade=t=out:st=%.3f:d=%.3f" % (fade_in, max(0, length - fade_out), fade_out),
                    "-c:a", "libvorbis", "-q:a", str(quality), dst], check=True)
    os.remove(tmp)
    return probe(dst)


def script_for(script, pack):
    lines = [list(entry) for entry in script["scripts"][pack["script"]]]
    at = next((i for i, entry in enumerate(lines) if entry[0] == "new_title"), len(lines) - 1) + 1
    lines[at:at] = [["title_%d" % (i + 2), "title", name + "."] for i, name in enumerate(script["titles"])]
    return lines


def lua_string(text):
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    if not KEY:
        sys.exit("Set ELEVENLABS_API_KEY.")
    args = sys.argv[1:]
    only_pack = args[args.index("--pack") + 1] if "--pack" in args else None
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else None
    jobs = int(args[args.index("--jobs") + 1]) if "--jobs" in args else 3
    redo = "--redo" in args
    script = json.load(open(os.path.join(HERE, "voice_script.json")))
    state_file = os.path.join(CACHE, "built.json")
    built = json.load(open(state_file)) if os.path.exists(state_file) else {}
    lengths, report, work = {}, {}, []

    for pack_id, pack in script["packs"].items():
        pack["id"] = pack_id
        pack["lines"] = script_for(script, pack)
        lengths[pack_id], report[pack_id] = {}, {}
        os.makedirs(os.path.join(OUT, pack_id), exist_ok=True)
        if pack.get("hit"):
            generated("hit", pack["hit"], 1.6)  # before the threads start, so it is asked for once
        names = set()
        for clip, kind, text in pack["lines"]:
            names.add(clip + ".ogg")
            dst = os.path.join(OUT, pack_id, clip + ".ogg")
            key = "%s/%s" % (pack_id, clip)
            # what this clip is made from; when any of it changes the clip is made again
            recipe = hashlib.md5(json.dumps([text, kind, pack["voice"], pack["pitch"], pack["speed"], pack["hall"], pack.get("hit"), pack.get("hit_lowpass"),
                                             pack.get("hit_db"), pack.get("gain"), pack.get("bass"), pack.get("delivery", {}).get(kind), clip in pack.get("stutter", []),
                                             CALL_TAKES if kind == "call" else 1, bool(pack.get("calm")), TREATMENT], sort_keys=True).encode()).hexdigest()[:12]
            chosen = (only_pack is None or pack_id == only_pack) and (only is None or clip in only)
            stale = not os.path.exists(dst) or built.get(key, {}).get("recipe") != recipe
            if chosen and (stale or redo):
                work.append((pack, clip, kind, text, dst, key, recipe))
            elif os.path.exists(dst):
                lengths[pack_id][clip] = probe(dst)
                report[pack_id][clip] = built.get(key, {})
        for leftover in sorted(set(os.listdir(os.path.join(OUT, pack_id))) - names):
            if only_pack is None and only is None:
                os.remove(os.path.join(OUT, pack_id, leftover))
                print("removed %s/%s (no longer in the script)" % (pack_id, leftover))

    def build(job, skip=()):
        pack, clip, kind, text, dst, key, recipe = job
        best, takes = choose(pack, clip, kind, text, skip)
        length = treat(best["path"], dst, kind, pack, stutter=clip in pack.get("stutter", []))
        entry = {"recipe": recipe, "text": spoken(text), "kind": kind, "heard": best["heard"].strip(), "match": round(best["score"], 2), "take": best["attempt"],
                 "takes": len(takes), "good_takes": sum(1 for t in takes if t["good"]), "speech": round(best["speech"], 2), "length": round(length, 2),
                 "bite": round(best["bite"], 1), "flag": "" if best["good"] else ("words" if best["score"] < GOOD_ENOUGH else ("long" if best["long"] else "gap"))}
        with print_lock:
            lengths[pack["id"]][clip], report[pack["id"]][clip], built[key] = length, entry, entry
            print("%-9s %-18s take %d of %d  %.2f  %4.1fs  heard: %s%s" % (pack["id"], clip, best["attempt"], len(takes), best["score"], length, entry["heard"],
                                                                         "   <-- " + entry["flag"].upper() if entry["flag"] else ""), flush=True)
        return entry

    failed = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = {pool.submit(build, job): job for job in work}
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except Exception as e:  # one line failing must not lose the rest
                failed.append((futures[future][5], str(e)))
                print("FAILED %s: %s" % failed[-1], flush=True)
            if len(built) % 20 == 0:
                with print_lock:
                    json.dump(built, open(state_file, "w"))
    os.makedirs(CACHE, exist_ok=True)
    json.dump(built, open(state_file, "w"))

    # sound effects and music
    sfx, music = {}, {}
    for name, spec in script.get("sfx", {}).items():
        dst = os.path.join(OUT, "sfx", name + ".ogg")
        recipe = hashlib.md5(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:12]
        if not os.path.exists(dst) or built.get("sfx/" + name, {}).get("recipe") != recipe:
            try:
                finish(generated("sfx_" + name, spec["prompt"], spec["seconds"]), dst, spec.get("loudness", -16), fade_out=spec.get("fade", 0.4), trim=spec.get("trim", True))
                # the same sound up a scale: name_1 is the sound itself, each step a few semitones higher
                for i, semitones in enumerate(spec.get("steps", []), 1):
                    ratio = 2 ** (semitones / 12.0)
                    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", dst, "-af", "asetrate=44100*%.5f,aresample=44100,atempo=%.5f" % (ratio, max(0.5, 1 / ratio ** 0.5)),
                                    "-c:a", "libvorbis", "-q:a", "4", os.path.join(OUT, "sfx", "%s_%d.ogg" % (name, i))], check=True)
                built["sfx/" + name] = {"recipe": recipe}
                print("sfx       %-18s %4.1fs" % (name, probe(dst)), flush=True)
            except Exception as e:
                failed.append(("sfx/" + name, str(e)))
        if os.path.exists(dst):
            sfx[name] = probe(dst)
            for i in range(1, len(spec.get("steps", [])) + 1):
                step = os.path.join(OUT, "sfx", "%s_%d.ogg" % (name, i))
                if os.path.exists(step):
                    sfx["%s_%d" % (name, i)] = probe(step)
    for name, spec in script.get("music", {}).items():
        dst = os.path.join(OUT, "music", name + ".ogg")
        recipe = hashlib.md5(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:12]
        raw = os.path.join(CACHE, "music_%s_%s.mp3" % (name, recipe))
        if not os.path.exists(dst) or built.get("music/" + name, {}).get("recipe") != recipe:
            try:
                if not os.path.exists(raw):
                    data = post("/music?output_format=mp3_44100_128", {"prompt": spec["prompt"], "music_length_ms": int(spec["seconds"] * 1000)})
                    with open(raw, "wb") as f:
                        f.write(data)
                finish(raw, dst, spec.get("loudness", -15), quality=4, fade_in=0.02, fade_out=1.2)
                built["music/" + name] = {"recipe": recipe}
                print("music     %-18s %4.1fs" % (name, probe(dst)), flush=True)
            except Exception as e:
                failed.append(("music/" + name, str(e)))
        if os.path.exists(dst):
            music[name] = probe(dst)
    json.dump(built, open(state_file, "w"))

    lines = ["-- Written by tools/build_voice.py from tools/voice_script.json. Do not edit by hand.",
             "-- Each announcer: its name in the options, how often it comes up in the mix, every clip",
             "-- with its length in seconds, and what each clip says.", "local _, ns = ...", "",
             "ns.VOICE_ORDER = { %s }" % ", ".join('"%s"' % p for p in script["packs"]), "", "ns.VOICE = {"]
    for pack_id, pack in script["packs"].items():
        lines.append("  %s = { label = %s, about = %s, weight = %d, clips = {" % (pack_id, lua_string(pack["label"]), lua_string(pack["about"]), pack.get("weight", 10)))
        for clip, _, _ in pack["lines"]:
            if clip in lengths[pack_id]:
                lines.append("    %s = %.2f," % (clip, lengths[pack_id][clip]))
        lines.append("  }, text = {")
        for clip, _, text in pack["lines"]:
            if clip in lengths[pack_id]:
                lines.append("    %s = %s," % (clip, lua_string(spoken(text))))
        lines.append("  } },")
    lines += ["}", "", "-- sounds under the voice, and the hunt theme for anyone without a song of their own",
              "ns.SFX = { %s }" % ", ".join("%s = %.2f" % item for item in sorted(sfx.items())),
              "ns.MUSIC = { %s }" % ", ".join("%s = %.2f" % item for item in sorted(music.items())), ""]
    with open(os.path.join(ROOT, "Godslayer", "Voice.lua"), "w") as f:
        f.write("\n".join(lines))

    # the report, and a page to listen from
    flagged, total = [], 0
    out = ["# Announcer build report", "",
           "Every clip, the take that was kept, and what the transcription heard. `match` is how closely the words",
           "heard match the script (1.00 is exact). `bite` is how much edge the voice has (higher is fiercer).", ""]
    for pack_id, pack in script["packs"].items():
        out += ["## %s (%s)" % (pack["label"], pack_id), "", "| clip | says | heard | match | take | good takes | seconds | bite | check |", "|---|---|---|---|---|---|---|---|---|"]
        for clip, kind, text in pack["lines"]:
            e = report[pack_id].get(clip)
            if not e or "match" not in e:
                continue
            total += 1
            if e["flag"]:
                flagged.append("%s/%s (%s)" % (pack_id, clip, e["flag"]))
            out.append("| %s | %s | %s | %.2f | %d | %d of %d | %.1f | %.1f | %s |" % (clip, e["text"], e["heard"], e["match"], e["take"], e["good_takes"], e["takes"], e["length"], e["bite"], e["flag"]))
        out.append("")
    out[4:4] = ["%d clips. Worth a listen: %s." % (total, ", ".join(flagged) if flagged else "none flagged"), ""]
    with open(os.path.join(HERE, "voice_report.md"), "w") as f:
        f.write("\n".join(out))

    page = ["<!doctype html><meta charset=utf-8><title>Godslayer announcers</title>",
            "<style>body{font:15px system-ui;background:#0b0a10;color:#e8e6df;max-width:1100px;margin:24px auto;padding:0 16px}h2{color:#ffd100;margin-top:32px}"
            "button{font:inherit;background:#1c1a26;color:#e8e6df;border:1px solid #3a3648;border-radius:6px;padding:6px 10px;margin:3px;cursor:pointer;text-align:left}"
            "button:hover{border-color:#ffd100}small{color:#8d8a99}.flag{border-color:#ff7c0a}p{color:#b9b6c6}</style>",
            "<h1>Godslayer announcers</h1><p>Click a line to hear it. Orange border: the build flagged it for a listen. Open this file from the tools folder so it can find the sounds.</p>",
            "<script>let a;function p(f){if(a)a.pause();a=new Audio('../Godslayer/Sounds/'+f+'.ogg');a.play()}</script>"]
    for pack_id, pack in script["packs"].items():
        page.append("<h2>%s</h2><p>%s</p>" % (html.escape(pack["label"]), html.escape(pack["about"])))
        for clip, kind, text in pack["lines"]:
            if clip in lengths[pack_id]:
                flag = report[pack_id].get(clip, {}).get("flag")
                page.append("<button%s onclick=\"p('%s/%s')\">%s <small>%s</small></button>" % (' class="flag"' if flag else "", pack_id, clip, html.escape(spoken(text)), clip))
    page.append("<h2>Sounds and music</h2>")
    for name in sorted(sfx):
        page.append("<button onclick=\"p('sfx/%s')\">%s</button>" % (name, name))
    for name in sorted(music):
        page.append("<button onclick=\"p('music/%s')\">%s (theme)</button>" % (name, name))
    with open(os.path.join(HERE, "audition.html"), "w") as f:
        f.write("\n".join(page))

    print("\n%d clips built this run, %d clips in all, %d worth a listen, %d failed." % (len(work) - len([x for x in failed if "/" in x[0] and not x[0].startswith(("sfx/", "music/"))]), total, len(flagged), len(failed)))
    for name, why in failed:
        print("  failed: %s  %s" % (name, why))


if __name__ == "__main__":
    main()
