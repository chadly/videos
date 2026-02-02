#!/bin/bash
# convert-nle.sh - Convert video to NLE-ready MP4
# Analyzes input, decides strategy, executes ffmpeg, returns JSON result

set -euo pipefail

# --- Configuration ---
MAX_WIDTH=3840
MAX_HEIGHT=2160
CRF=18
PRESET="slow"
AUDIO_BITRATE_STEREO="256k"
AUDIO_BITRATE_MONO="192k"

# --- Helper Functions ---
json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")'
}

output_json() {
  local status="$1"
  shift
  printf '{\n  "status": "%s"' "$status"
  while [[ $# -gt 0 ]]; do
    printf ',\n  %s' "$1"
    shift
  done
  printf '\n}\n'
}

needs_review() {
  local reason="$1"
  local details="$2"
  local probe_excerpt="${3:-}"

  if [[ -n "$probe_excerpt" ]]; then
    output_json "needs_review" \
      "\"reason\": \"$reason\"" \
      "\"details\": $(json_escape "$details")" \
      "\"probe_data\": $probe_excerpt"
  else
    output_json "needs_review" \
      "\"reason\": \"$reason\"" \
      "\"details\": $(json_escape "$details")"
  fi
  exit 0
}

# --- Input Validation ---
if [[ $# -lt 1 ]]; then
  output_json "error" '"reason": "missing_input"' '"details": "Usage: convert-nle.sh <input_file>"'
  exit 1
fi

INPUT="$1"
if [[ ! -f "$INPUT" ]]; then
  output_json "error" '"reason": "file_not_found"' "\"details\": \"File not found: $INPUT\""
  exit 1
fi

OUTPUT="${INPUT%.*}.mp4"

# --- Probe Video Stream ---
VIDEO_PROBE=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,width,height,pix_fmt,r_frame_rate,bit_rate \
  -of json "$INPUT" 2>/dev/null) || {
  needs_review "probe_failed" "Could not probe video stream"
}

VIDEO_CODEC=$(echo "$VIDEO_PROBE" | jq -r '.streams[0].codec_name // empty')
VIDEO_WIDTH=$(echo "$VIDEO_PROBE" | jq -r '.streams[0].width // empty')
VIDEO_HEIGHT=$(echo "$VIDEO_PROBE" | jq -r '.streams[0].height // empty')
VIDEO_PIX_FMT=$(echo "$VIDEO_PROBE" | jq -r '.streams[0].pix_fmt // empty')

if [[ -z "$VIDEO_CODEC" ]]; then
  needs_review "no_video_stream" "No video stream found in file"
fi

# --- Probe Audio Streams ---
AUDIO_PROBE=$(ffprobe -v error -select_streams a \
  -show_entries stream=index,codec_name,channels,sample_rate:stream_tags=language \
  -of json "$INPUT" 2>/dev/null) || {
  needs_review "probe_failed" "Could not probe audio streams"
}

AUDIO_COUNT=$(echo "$AUDIO_PROBE" | jq '.streams | length')

if [[ "$AUDIO_COUNT" -eq 0 ]]; then
  needs_review "no_audio_stream" "No audio stream found in file"
fi

# --- Video Strategy ---
VIDEO_OPTS=""
VIDEO_SUMMARY=""
NEEDS_SCALE=false

# Check if resolution exceeds 4K
if [[ -n "$VIDEO_WIDTH" && -n "$VIDEO_HEIGHT" ]]; then
  if [[ "$VIDEO_WIDTH" -gt "$MAX_WIDTH" || "$VIDEO_HEIGHT" -gt "$MAX_HEIGHT" ]]; then
    NEEDS_SCALE=true
  fi
fi

# Determine video codec strategy
case "$VIDEO_CODEC" in
  h264|hevc|h265)
    if [[ "$NEEDS_SCALE" == "true" ]]; then
      VIDEO_OPTS="-c:v libx264 -crf $CRF -preset $PRESET -pix_fmt yuv420p -vf scale='min($MAX_WIDTH,iw)':min'($MAX_HEIGHT,ih)':force_original_aspect_ratio=decrease"
      VIDEO_SUMMARY="transcode video ($VIDEO_CODEC ${VIDEO_WIDTH}x${VIDEO_HEIGHT} → h264, scaled to fit 4K)"
    else
      VIDEO_OPTS="-c:v copy"
      VIDEO_SUMMARY="remux video ($VIDEO_CODEC)"
    fi
    ;;
  prores|dnxhd|dnxhr|vp8|vp9|av1|mpeg2video|mpeg4|wmv*|msmpeg*)
    VIDEO_OPTS="-c:v libx264 -crf $CRF -preset $PRESET -pix_fmt yuv420p"
    if [[ "$NEEDS_SCALE" == "true" ]]; then
      VIDEO_OPTS="$VIDEO_OPTS -vf scale='min($MAX_WIDTH,iw)':min'($MAX_HEIGHT,ih)':force_original_aspect_ratio=decrease"
    fi
    VIDEO_SUMMARY="transcode video ($VIDEO_CODEC → h264)"
    ;;
  *)
    # Unknown codec - flag for review
    needs_review "unknown_video_codec" "Unknown video codec: $VIDEO_CODEC" "$VIDEO_PROBE"
    ;;
esac

# --- Audio Strategy ---

# Find English audio tracks
ENG_TRACKS=$(echo "$AUDIO_PROBE" | jq '[.streams[] | select(.tags.language != null and (.tags.language | test("^(eng?|english)$"; "i")))]')
ENG_COUNT=$(echo "$ENG_TRACKS" | jq 'length')

# Find tracks with no language tag
NO_LANG_TRACKS=$(echo "$AUDIO_PROBE" | jq '[.streams[] | select(.tags.language == null)]')
NO_LANG_COUNT=$(echo "$NO_LANG_TRACKS" | jq 'length')

SELECTED_AUDIO=""
AUDIO_INDEX=""
AUDIO_CODEC=""
AUDIO_CHANNELS=""

if [[ "$ENG_COUNT" -gt 1 ]]; then
  # Multiple English tracks - need user choice
  TRACK_DETAILS=$(echo "$ENG_TRACKS" | jq -r '.[] | "Stream \(.index): \(.codec_name) \(.channels)ch"' | tr '\n' ', ' | sed 's/, $//')
  needs_review "multiple_english_audio" "Found $ENG_COUNT English audio tracks: $TRACK_DETAILS" "$ENG_TRACKS"
elif [[ "$ENG_COUNT" -eq 1 ]]; then
  SELECTED_AUDIO="$ENG_TRACKS"
  AUDIO_INDEX=$(echo "$SELECTED_AUDIO" | jq -r '.[0].index')
  AUDIO_CODEC=$(echo "$SELECTED_AUDIO" | jq -r '.[0].codec_name')
  AUDIO_CHANNELS=$(echo "$SELECTED_AUDIO" | jq -r '.[0].channels')
elif [[ "$AUDIO_COUNT" -eq 1 ]]; then
  # Only one audio track, use it
  SELECTED_AUDIO=$(echo "$AUDIO_PROBE" | jq '.streams')
  AUDIO_INDEX=$(echo "$SELECTED_AUDIO" | jq -r '.[0].index')
  AUDIO_CODEC=$(echo "$SELECTED_AUDIO" | jq -r '.[0].codec_name')
  AUDIO_CHANNELS=$(echo "$SELECTED_AUDIO" | jq -r '.[0].channels')
elif [[ "$NO_LANG_COUNT" -eq "$AUDIO_COUNT" ]]; then
  # All tracks missing language tags
  if [[ "$AUDIO_COUNT" -gt 1 ]]; then
    TRACK_DETAILS=$(echo "$AUDIO_PROBE" | jq -r '.streams[] | "Stream \(.index): \(.codec_name) \(.channels)ch"' | tr '\n' ', ' | sed 's/, $//')
    needs_review "missing_language_tags" "No language tags on $AUDIO_COUNT audio tracks: $TRACK_DETAILS" "$AUDIO_PROBE"
  else
    # Single track with no language
    SELECTED_AUDIO=$(echo "$AUDIO_PROBE" | jq '.streams')
    AUDIO_INDEX=$(echo "$SELECTED_AUDIO" | jq -r '.[0].index')
    AUDIO_CODEC=$(echo "$SELECTED_AUDIO" | jq -r '.[0].codec_name')
    AUDIO_CHANNELS=$(echo "$SELECTED_AUDIO" | jq -r '.[0].channels')
  fi
else
  # Multiple tracks but no English - use first track
  SELECTED_AUDIO=$(echo "$AUDIO_PROBE" | jq '[.streams[0]]')
  AUDIO_INDEX=$(echo "$SELECTED_AUDIO" | jq -r '.[0].index')
  AUDIO_CODEC=$(echo "$SELECTED_AUDIO" | jq -r '.[0].codec_name')
  AUDIO_CHANNELS=$(echo "$SELECTED_AUDIO" | jq -r '.[0].channels')
fi

# Determine audio conversion strategy
AUDIO_OPTS=""
AUDIO_SUMMARY=""

if [[ -z "$AUDIO_CHANNELS" || "$AUDIO_CHANNELS" == "null" ]]; then
  AUDIO_CHANNELS=2  # Default to stereo if unknown
fi

case "$AUDIO_CHANNELS" in
  1)
    # Mono → stereo AAC
    AUDIO_OPTS="-ac 2 -c:a aac -b:a $AUDIO_BITRATE_MONO"
    AUDIO_SUMMARY="transcode audio ($AUDIO_CODEC mono → aac stereo)"
    ;;
  2)
    # Stereo
    if [[ "$AUDIO_CODEC" == "aac" ]]; then
      AUDIO_OPTS="-c:a copy"
      AUDIO_SUMMARY="remux audio (aac stereo)"
    else
      AUDIO_OPTS="-c:a aac -b:a $AUDIO_BITRATE_STEREO"
      AUDIO_SUMMARY="transcode audio ($AUDIO_CODEC stereo → aac stereo)"
    fi
    ;;
  *)
    # Surround → stereo AAC
    AUDIO_OPTS="-ac 2 -c:a aac -b:a $AUDIO_BITRATE_STEREO"
    AUDIO_SUMMARY="transcode audio ($AUDIO_CODEC ${AUDIO_CHANNELS}ch → aac stereo)"
    ;;
esac

# --- Check if Already Optimized ---
INPUT_EXT="${INPUT##*.}"
if [[ "${INPUT_EXT,,}" == "mp4" && "$VIDEO_OPTS" == "-c:v copy" && "$AUDIO_OPTS" == "-c:a copy" ]]; then
  output_json "ok" \
    "\"input\": $(json_escape "$INPUT")" \
    "\"output\": $(json_escape "$OUTPUT")" \
    '"summary": "already optimized - no conversion needed"' \
    '"skipped": true'
  exit 0
fi

# --- Build and Execute ffmpeg Command ---
FFMPEG_CMD="ffmpeg -i $(printf '%q' "$INPUT") -map 0:v:0 $VIDEO_OPTS -map 0:$AUDIO_INDEX $AUDIO_OPTS -movflags +faststart $(printf '%q' "$OUTPUT")"

# Execute ffmpeg (quiet on success, capture errors)
FFMPEG_LOG=$(mktemp)
trap 'rm -f "$FFMPEG_LOG"' EXIT

if ffmpeg -y -v error -i "$INPUT" \
  -map 0:v:0 $VIDEO_OPTS \
  -map 0:$AUDIO_INDEX $AUDIO_OPTS \
  -movflags +faststart \
  "$OUTPUT" </dev/null 2>"$FFMPEG_LOG"; then

  # Success - minimal JSON output
  SUMMARY="$VIDEO_SUMMARY, $AUDIO_SUMMARY"
  output_json "ok" \
    "\"input\": $(json_escape "$INPUT")" \
    "\"output\": $(json_escape "$OUTPUT")" \
    "\"summary\": $(json_escape "$SUMMARY")"
else
  # Error - include ffmpeg output
  FFMPEG_ERR=$(cat "$FFMPEG_LOG")
  output_json "error" \
    '"reason": "ffmpeg_failed"' \
    "\"details\": $(json_escape "$FFMPEG_ERR")"
  exit 1
fi
