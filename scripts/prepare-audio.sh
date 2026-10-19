#!/bin/zsh
set -eu
cd "${0:A:h}/.."
ffmpeg -v error -y -i Assets/audio/reset-confirmed.wav \
  -af 'atempo=1.04,equalizer=f=2800:t=q:w=1:g=1.5,loudnorm=I=-17:TP=-2:LRA=7' \
  -ar 44100 -ac 1 -c:a pcm_s16le Assets/audio/reset-confirmed.caf
ffmpeg -v error -y -i Assets/audio/reset-confirmed.caf -codec:a libmp3lame -b:a 128k Assets/audio/reset-confirmed.mp3
