---
name: convert-to-mp4
description: >-
  Convert video files to MP4 container format for non-linear editing (NLE).
  Scans current directory for .mkv files, analyzes them, and batch converts.
  Use when the user wants to convert videos for editing software like Premiere,
  DaVinci Resolve, or Final Cut, or mentions remuxing/transcoding to MP4.
---

# Convert Video to MP4 for NLE

## Step 1: Check Prerequisites

Verify destination exists:
```bash
[ -d "/mnt/d/Videos/movies" ] && echo "OK" || echo "MISSING"
```
If missing, warn user and stop.

## Step 2: Discover Video Files

Scan current directory for `.mkv` files:
```bash
ls -1 *.mkv 2>/dev/null
```
If no files found, inform user and stop.

## Step 3: Analyze and Confirm

For each file, run ffprobe to analyze:
```bash
ffprobe -v quiet -print_format json -show_streams "<file>"
```

Build a summary table showing for each file:
| File | Video | Audio |
|------|-------|-------|
| movie.mkv | remux hevc 1080p | transcode dts 5.1 → aac stereo |

Determine strategy per stream:
- **Video**: h264/hevc → remux; other (vp9, av1, etc.) → transcode to h264
- **Audio**: aac stereo → remux; other → transcode to aac stereo

Tell user:
- Originals will be deleted after successful conversion
- Outputs go to `/mnt/d/Videos/movies/`

Ask for confirmation before proceeding.

## Step 4: Batch Process

Process each file sequentially:
```bash
./.claude/skills/convert-to-mp4/convert-nle.sh "<file>"
```

Handle each result:

| Status | Action |
|--------|--------|
| `ok` | Delete original, move `.mp4` to `/mnt/d/Videos/movies/`, log success |
| `ok` + `skipped` | File already optimized, skip cleanup, log skipped |
| `needs_review` | Note the reason, keep original, continue to next file |
| `error` | Report error, keep original, continue to next file |

## Step 5: Cleanup (on success)

```bash
rm "<original_file>"
mv "<output_file>.mp4" "/mnt/d/Videos/movies/"
```

## Step 6: Summary

After all files processed, report:
- Files converted successfully (with destinations)
- Files skipped (with reasons: already optimized, needs_review reason, or error)

## Handling needs_review Cases

When a file returns `needs_review`, note the reason for the summary:

| Reason | Summary Note |
|--------|--------------|
| `multiple_english_audio` | "Multiple English tracks - user must choose" |
| `missing_language_tags` | "No language tags - user must choose audio track" |
| `unknown_video_codec` | "Unknown codec - manual review needed" |
| `no_video_stream` | "No video stream found" |
| `no_audio_stream` | "No audio stream found" |

## Manual ffmpeg Template (for edge cases resolved later)

```bash
ffmpeg -i "<input_file>" \
  -map 0:v:0 <video_options> \
  -map 0:<audio_stream_index> <audio_options> \
  -movflags +faststart \
  "<output_file>.mp4"
```

### Video Options
- Copy compatible codec: `-c:v copy`
- Transcode: `-c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p`

### Audio Options
- Copy AAC stereo: `-c:a copy`
- Transcode to stereo: `-ac 2 -c:a aac -b:a 256k`
