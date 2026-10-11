#!/usr/bin/env python3
"""Re-pitch the Godslayer announcer so it sits in the key of your kill song.

    python3 tools/tune_announcer.py /path/to/Interface/AddOns/GodslayerMusic/kill.mp3

It works out the song's key, measures the pitch each announcer line is shouted at, and moves
each line by the smallest step that puts it on a note of the key's home chord (root, third or
fifth), so no line moves far enough to change the character of the voice. The results go in a "voice" folder next to the song, where the addon
looks first. Needs ffmpeg, numpy and scipy. Delete the voice folder to go back to the built-in lines.
"""
import os
import subprocess
import sys

import numpy as np
from scipy.signal import stft

NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
RATE = 22050
MAX_SHIFT = 2.5


def decode(path, seconds=None):
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le"]
    if seconds:
        cmd[3:3] = ["-t", str(seconds)]
    out = subprocess.run(cmd + ["-"], capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.float32)


def song_key(samples):
    """Krumhansl-Schmuckler: fold the spectrum onto twelve pitch classes and match key profiles."""
    freqs, _, spec = stft(samples, fs=RATE, nperseg=8192, noverlap=4096)
    power = (np.abs(spec) ** 2).sum(axis=1)
    keep = (freqs >= 55) & (freqs <= 2000)
    classes = np.round(12 * np.log2(freqs[keep] / 440.0) + 9).astype(int) % 12  # 0 = C
    chroma = np.bincount(classes, weights=power[keep], minlength=12)
    chroma = chroma / chroma.sum()
    best = None
    for tonic in range(12):
        for name, profile in (("major", MAJOR), ("minor", MINOR)):
            score = np.corrcoef(chroma, np.roll(profile, tonic))[0, 1]
            if best is None or score > best[0]:
                best = (score, tonic, name)
    return best[1], best[2], best[0]


def voice_pitch(samples):
    """Median pitch of the voiced parts of a line, by autocorrelation, in Hz."""
    frame, hop = 1024, 256
    lo, hi = int(RATE / 420), int(RATE / 75)
    loud = np.sqrt(np.mean(samples ** 2)) * 0.6
    found = []
    for start in range(0, len(samples) - frame, hop):
        chunk = samples[start:start + frame] * np.hanning(frame)
        if np.sqrt(np.mean(chunk ** 2)) < loud * 0.5:
            continue
        corr = np.correlate(chunk, chunk, mode="full")[frame - 1:]
        if corr[0] <= 0:
            continue
        lag = lo + int(np.argmax(corr[lo:hi]))
        if corr[lag] / corr[0] > 0.45:
            found.append(RATE / lag)
    return float(np.median(found)) if found else None


def shift_for(pitch_hz, tonic, mode):
    """Semitones to the nearest note of the key's home chord: root, third or fifth."""
    midi = 69 + 12 * np.log2(pitch_hz / 440.0)
    best = None
    for target_class in (tonic, (tonic + (3 if mode == "minor" else 4)) % 12, (tonic + 7) % 12):
        delta = ((target_class - midi + 6) % 12) - 6
        if best is None or abs(delta) < abs(best):
            best = delta
    return float(max(-MAX_SHIFT, min(MAX_SHIFT, best)))


def repitch(src, dst, semitones):
    ratio = 2 ** (semitones / 12.0)
    tempo = 1 / ratio
    chain = "asetrate=44100*%.6f,aresample=44100,atempo=%.6f" % (ratio, tempo)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-af", chain, "-ac", "1", "-ar", "44100",
                    "-c:a", "libvorbis", "-q:a", "5", dst], check=True)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    song = sys.argv[1]
    here = os.path.dirname(os.path.abspath(__file__))
    lines = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "..", "Godslayer", "Sounds")
    out = os.path.join(os.path.dirname(os.path.abspath(song)), "voice")
    tonic, mode, score = song_key(decode(song, seconds=240))
    print("Song key: %s %s (match %.2f)" % (NOTES[tonic], mode, score))
    if score < 0.5:
        print("That match is weak, so the key may be wrong. The lines are still moved, by small steps only.")
    os.makedirs(out, exist_ok=True)
    for name in sorted(os.listdir(lines)):
        if not name.endswith(".ogg"):
            continue
        src = os.path.join(lines, name)
        pitch = voice_pitch(decode(src))
        if not pitch:
            print("  %-20s no steady pitch found, copied as it is" % name)
            repitch(src, os.path.join(out, name), 0.0)
            continue
        step = shift_for(pitch, tonic, mode)
        repitch(src, os.path.join(out, name), step)
        print("  %-20s shouted near %.0f Hz, moved %+.1f semitones" % (name, pitch, step))
    print("Written to " + out + ". Restart the game to hear them.")


if __name__ == "__main__":
    main()
