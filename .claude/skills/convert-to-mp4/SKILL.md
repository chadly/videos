---
name: convert-to-mp4
description: >-
  Convert video files to MP4 container format for non-linear editing (NLE).
  Analyzes input with ffprobe and generates ffmpeg commands without executing them.
  Use when the user wants to convert videos for editing software like Premiere,
  DaVinci Resolve, or Final Cut, or mentions remuxing/transcoding to MP4.
---

# Convert Video to MP4 for NLE

Analyze video files and generate ffmpeg commands to convert them to MP4 format for NLEs. **Do not execute the ffmpeg command** - only output it for the user to run.

## Step 1: Analyze the Input File

```bash
ffprobe -v error -show_format -show_streams -print_format json "<input_file>"
```

Parse the output to identify:
- **Video streams**: codec, resolution, frame rate, bit rate, pixel format, color space
- **Audio streams**: codec, channels, sample rate, language tags (`tags.language`)
- **Container format**: current format and compatibility

## Step 2: Determine Conversion Strategy

### Video Rules
1. If video exceeds 4K (3840x2160), scale down to 4K maintaining aspect ratio
2. H.264 or H.265/HEVC in MP4-compatible pixel formats → **remux** (copy)
3. ProRes, DNxHD, or other codecs → **transcode**: `-c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p`
4. Always preserve frame rate and color metadata

### Audio Rules
1. Find the first English audio track (`tags.language`: `eng`, `en`, or `english`, case-insensitive)
2. If no English track found, use the first audio track and note this
3. Channel conversion:
   - Stereo + AAC → **remux** (copy)
   - Stereo + other codec → **transcode** to AAC
   - Surround (>2 channels) → **downmix**: `-ac 2 -c:a aac -b:a 256k`
   - Mono → `-ac 2 -c:a aac -b:a 192k`

### Container Rules
- Output: `.mp4` container
- Use `-movflags +faststart` for NLE compatibility

## Step 3: Generate Commands

**Conversion command template:**
```bash
ffmpeg -i "<input_file>" \
  -map 0:v:0 <video_options> \
  -map 0:<audio_stream_index> <audio_options> \
  -movflags +faststart \
  "<output_file>.mp4"
```

**Verification command:**
```bash
ffprobe -v error -show_format -show_streams -print_format json "<output_file>.mp4"
```

## Step 4: Present Results

### Example Output

```
## Input Analysis
- Container: MKV
- Video: HEVC 3840x2160 @ 23.976fps, ~15 Mbps
- Audio Track 0: DTS-HD MA 7.1 (English)
- Audio Track 1: AAC Stereo (Spanish)

## Conversion Plan
- Video: Copy (HEVC is MP4 compatible)
- Audio: Transcode Track 0 (DTS-HD 7.1) → AAC Stereo 256kbps

## ffmpeg Command
ffmpeg -i "input.mkv" \
  -map 0:v:0 -c:v copy \
  -map 0:a:0 -ac 2 -c:a aac -b:a 256k \
  -movflags +faststart \
  "input.mp4"

## Verification
After conversion, run:
ffprobe -v error -show_format -show_streams -print_format json "input.mp4"

Expected: video=hevc, audio=aac stereo, container=mp4
```

## Notes
- If input is already optimized MP4 with stereo AAC, inform user no conversion may be needed
- Warn if quality loss is expected (e.g., transcoding from high-quality source)
- If multiple English audio tracks exist, use the first one and mention others
