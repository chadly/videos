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

For each file, run the script in analyze mode:
```bash
./.claude/skills/convert-to-mp4/convert-nle.sh --analyze "<file>"
```

Build a summary table from JSON output:
| File | Video | Audio |
|------|-------|-------|
| movie.mkv | `video_summary` | `audio_summary` |

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
| `needs_review` | Note the reason from JSON, keep original, continue to next file |
| `error` | Report error, keep original, continue to next file |

## Step 5: Cleanup (on success)

```bash
rm "<original_file>"
mv "<output_file>.mp4" "/mnt/d/Videos/movies/"
```

## Step 6: Summary

After all files processed, report:
- Files converted successfully (with destinations)
- Files skipped (with reasons from script output)
