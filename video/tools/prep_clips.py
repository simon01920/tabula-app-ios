#!/usr/bin/env python3
"""Cut the edit's clips from the raw simulator recordings (video/captures/) into the Hyperframes project.

Raw `simctl io recordVideo` files are variable-frame-rate, and their DTS lag PTS by ~93 s. With default flags,
ffmpeg filters follow the DTS and pick the wrong frames, so every read uses `-fflags +igndts` (presentation
timestamps only). Each clip: trim [in, in+dur) in source PTS seconds -> constant 30 fps -> Lanczos scale
1320x2868 -> 880x1912 (2/3, same aspect; headroom for the camera zoom inside the bezel) -> H.264 CRF 12 yuv420p, no audio. No speed change, no crop, no
retouching. The table below is the trim record that capture-manifest.md cites.

Run from the repo root: python3 video/tools/prep_clips.py [name ...]
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CAP = os.path.join(ROOT, "video", "captures")
OUT = os.path.join(ROOT, "video", "app-preview-2026-11-04", "composition", "assets", "clips")
R3 = "run-41748424916/app-preview-3/video-out"   # https://github.com/simon01920/tabula-app-ios/actions/runs/41748424916
R5 = "run-41761857082/app-preview-5/video-out"   # https://github.com/simon01920/tabula-app-ios/actions/runs/41761857082

# name: (source relative to video/captures, in seconds (source PTS), duration seconds, what it shows)
CLIPS = {
    # v2 edit (2026-11-04, showcase pass): keep the real UI motion (taps, sheets, pushes, scroll) instead of static holds.
    "c1a_today": (f"{R3}/S1_today_to_week/S1_today_to_week.mp4", 64.8, 2.0,
                  "Today (NOW Mathematics, Next Biology) -> real tap on the Timetable tab (highlight moves at 66.5)"),
    "c1b_week": (f"{R3}/S1_today_to_week/S1_today_to_week.mp4", 69.95, 1.8,
                 "Week grid as it renders (70.0). The ~3.5 s CI-simulator tap-to-render lag (66.5 -> 70.0) is cut with a dissolve"),
    "c2b_reading": (f"{R5}/S2_photo_import/S2_photo_import.mp4", 232.4, 2.6,
                    "Reading Timetable (own photo, steps finishing) -> real transition into the Check Timetable review (233.84) -> review hold"),
    "c2c_approve": (f"{R5}/S2_photo_import/S2_photo_import.mp4", 241.4, 1.6,
                    "Same review screen -> real Approve tap (242.0) -> Add Timetable sheet starts to rise"),
    "c2d_week": (f"{R5}/S2_photo_import/S2_photo_import.mp4", 246.7, 1.4,
                 "Real 'Add as New Timetable' tap -> the imported week appears (246.8)"),
    "c3a_lesson": (f"{R5}/S3_lesson_homework/S3_lesson_homework.mp4", 99.6, 2.0,
                   "Week grid -> real tap on Wed P1 Mathematics -> lesson sheet rises (100.4-101.1) with its task"),
    "c3b_task": (f"{R5}/S3_lesson_homework/S3_lesson_homework.mp4", 104.6, 1.3,
                 "Real tap on 'Finish algebra exercises' -> task sheet (104.8-105.75)"),
    "c3c_tick": (f"{R5}/S3_lesson_homework/S3_lesson_homework.mp4", 111.45, 1.3,
                 "Real tick of 'Questions 1-10' (111.82) -> 1/2"),
    "c4a_exams": (f"{R3}/S4_exam/S4_exam.mp4", 99.9, 2.0,
                  "Today -> real tap on the Exams tab -> Exams list (Biology quiz, in 3 days)"),
    "c4b_detail": (f"{R3}/S4_exam/S4_exam.mp4", 106.9, 2.4,
                   "Real tap on Biology quiz (107.18) -> exam detail push (108.0-108.6)"),
    "c5a_exam_reminder": (f"{R3}/S4_exam/S4_exam.mp4", 115.9, 2.4,
                          "Edit Exam (opened via the real Edit button; later cancelled): real scroll down to Reminders: Remind me on, 1 day before 18:00"),
    "c5b_reminders": (f"{R3}/S5_reminders/S5_reminders.mp4", 144.5, 2.8,
                      "Settings -> real tap on Reminders (144.8) -> push -> per-kind rows, quiet hours, loud alarms"),
    "c6a_day": (f"{R3}/S8a_day/S8a_day.mp4", 50.0, 2.0, "Day view (time blocks), 10:20 now line on Mathematics"),
    "c6b_tiles": (f"{R3}/S8b_tiles/S8b_tiles.mp4", 56.3, 2.0, "Tiles view, Mathematics NOW"),
    "c6c_week": (f"{R3}/S1_today_to_week/S1_today_to_week.mp4", 72.4, 3.6,
                 "Week grid (static hold) under the text-only 'Also in Tabula' mention"),
    "c7_today": (f"{R3}/S1_today_to_week/S1_today_to_week.mp4", 62.3, 3.2, "Today (static hold) for the close"),
}


def cut(name):
    src, start, dur, _ = CLIPS[name]
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, f"{name}.mp4")
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-fflags", "+igndts",
           "-i", os.path.join(CAP, src), "-ss", f"{start}", "-t", f"{dur}",
           "-vf", "fps=30,scale=880:1912:flags=lanczos,setsar=1",
           "-c:v", "libx264", "-preset", "slow", "-crf", "12", "-pix_fmt", "yuv420p", "-an",
           "-movflags", "+faststart", dst]
    subprocess.run(cmd, check=True)
    print(f"{name}: {src} [{start}, {start + dur}) -> {os.path.relpath(dst, ROOT)}")


if __name__ == "__main__":
    for n in sys.argv[1:] or CLIPS:
        cut(n)
