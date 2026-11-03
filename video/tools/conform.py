#!/usr/bin/env python3
"""Conform a Hyperframes render to the App Store app-preview contract (checked 2026-11-04):
886x1920 portrait, 29.0 s, constant 30 fps, H.264 High <= Level 4.0, progressive, 10-12 Mbps, yuv420p, BT.709 SDR,
square pixels, fast start; AAC 256 kbps, 48 kHz, stereo. Audio gets two-pass EBU R128 loudness normalisation
to -16 LUFS integrated, -1.5 dBTP (editorial target, not an Apple rule).

Usage: python3 video/tools/conform.py <render.mp4> <out.mp4>
"""
import json
import os
import subprocess
import sys
import tempfile


def run(cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True)


def main(src, dst):
    measure = run(["ffmpeg", "-hide_banner", "-nostats", "-i", src, "-vn",
                   "-af", "loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"]).stderr
    m = json.loads(measure[measure.rindex("{"):measure.rindex("}") + 1])
    af = ("loudnorm=I=-16:TP=-1.5:LRA=11:linear=true:"
          f"measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}:"
          f"measured_thresh={m['input_thresh']}:offset={m['target_offset']},aresample=48000")
    video = ["-vf", "fps=30,scale=886:1920:flags=lanczos,setsar=1,format=yuv420p",
             "-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-level:v", "4.0",
             # CBR with HRD filler: static screen content otherwise undershoots Apple's 10-12 Mbps target (~2 Mbps ABR).
             "-b:v", "11M", "-minrate", "11M", "-maxrate", "11M", "-bufsize", "11M",
             "-x264-params", "nal-hrd=cbr:force-cfr=1", "-g", "30", "-bf", "2",
             "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv"]
    with tempfile.TemporaryDirectory() as tmp:
        log = os.path.join(tmp, "x264")
        run(["ffmpeg", "-hide_banner", "-y", "-i", src, *video, "-pass", "1", "-passlogfile", log, "-an",
             "-t", "29", "-f", "mp4", os.devnull])
        run(["ffmpeg", "-hide_banner", "-y", "-i", src, *video, "-pass", "2", "-passlogfile", log,
             "-af", af, "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
             "-t", "29", "-movflags", "+faststart", dst])
    print("conformed", dst, "| source loudness", m["input_i"], "LUFS", m["input_tp"], "dBTP")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
