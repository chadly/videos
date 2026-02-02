---
name: convert-to-mp4
description: >-
  Convert video files to MP4 container format for non-linear editing (NLE).
  Uses convert-nle.sh to analyze and convert automatically.
  Use when the user wants to convert videos for editing software like Premiere,
  DaVinci Resolve, or Final Cut, or mentions remuxing/transcoding to MP4.
---

# Convert Video to MP4 for NLE

Run the conversion script:

```bash
./.claude/skills/convert-to-mp4/convert-nle.sh "<input_file>"
```

## Handling Results

**If status is "ok"**: Report the summary to the user. Conversion is complete. Example response:

> Converted `input.mkv` to `input.mp4`
> - Video: remuxed (hevc)
> - Audio: transcoded (dts 5.1 → aac stereo)

**If status is "ok" with "skipped": true**: The file is already optimized. Inform the user no conversion was needed.

**If status is "needs_review"**: The script found an edge case requiring user input. Analyze the `probe_data` and `reason`:

| Reason | Action |
|--------|--------|
| `multiple_english_audio` | Ask user which track to use, then run ffmpeg manually |
| `missing_language_tags` | Ask user which track to use, then run ffmpeg manually |
| `unknown_video_codec` | Analyze codec and decide: transcode to h264 or flag as unsupported |
| `no_video_stream` | Inform user the file has no video |
| `no_audio_stream` | Inform user the file has no audio |

**If status is "error"**: Report the error to the user.

## Manual ffmpeg Template (for edge cases)

When you need to run ffmpeg manually after user input:

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
- Mono to stereo: `-ac 2 -c:a aac -b:a 192k`
