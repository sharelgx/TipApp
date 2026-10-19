#!/bin/zsh
set -eu
cd "${0:A:h}/.."
kind="${1:-confirmed}"
case "$kind" in
  confirmed|planned) ;;
  *) echo "Usage: $0 [confirmed|planned]" >&2; exit 2 ;;
esac
ffmpeg -v error -y -i "Assets/audio/reset-${kind}.wav" \
  -af 'atempo=1.04,equalizer=f=2800:t=q:w=1:g=1.5,loudnorm=I=-17:TP=-2:LRA=7' \
  -ar 44100 -ac 1 -c:a pcm_s16le "Assets/audio/reset-${kind}.caf"
ffmpeg -v error -y -i "Assets/audio/reset-${kind}.caf" -codec:a libmp3lame -b:a 128k "Assets/audio/reset-${kind}.mp3"
