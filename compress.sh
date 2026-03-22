#!/bin/bash

set -e

INPUT="$1"
OUTPUT="${2:-saida.mp4}"
TARGET_MB=200
MARGIN_MB=5

if [[ -z "$INPUT" ]]; then
  echo "Uso: $0 input.mp4 [output.mp4]"
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "Arquivo não encontrado: $INPUT"
  exit 1
fi

echo "📥 Input: $INPUT"
echo "📤 Output: $OUTPUT"

# duração
DURATION=$(ffprobe -v error -show_entries format=duration \
-of default=noprint_wrappers=1:nokey=1 "$INPUT")

DURATION=${DURATION%.*}

if [[ -z "$DURATION" || "$DURATION" -le 0 ]]; then
  echo "Erro ao obter duração"
  exit 1
fi

echo "⏱ Duração: ${DURATION}s"

RES=$(ffprobe -v error -select_streams v:0 \
-show_entries stream=width,height \
-of csv=s=x:p=0 "$INPUT")

echo "📺 Resolução original: $RES"

TARGET_BITS=$(( (TARGET_MB - MARGIN_MB) * 1024 * 1024 * 8 ))
AUDIO=128000

# cores ANSI
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

progress_bar () {
  START_TIME=$(date +%s)

  while read -r line; do
    if [[ $line == out_time_ms=* ]]; then
      OUT_MS=${line#*=}
      OUT_SEC=$((OUT_MS / 1000000))
      PERCENT=$((OUT_SEC * 100 / DURATION))

      NOW=$(date +%s)
      ELAPSED=$((NOW - START_TIME))

      if [[ "$OUT_SEC" -gt 0 ]]; then
        RATE=$((ELAPSED * (DURATION - OUT_SEC) / OUT_SEC))
      else
        RATE=0
      fi

      ETA_MIN=$((RATE / 60))
      ETA_SEC=$((RATE % 60))

      # cor dinâmica
      if [[ $PERCENT -lt 50 ]]; then
        COLOR=$RED
      elif [[ $PERCENT -lt 80 ]]; then
        COLOR=$YELLOW
      else
        COLOR=$GREEN
      fi

      FILLED=$((PERCENT / 2))
      EMPTY=$((50 - FILLED))

      BAR=$(printf "%0.s#" $(seq 1 $FILLED))
      SPACE=$(printf "%0.s-" $(seq 1 $EMPTY))

      printf "\r${COLOR}[%s%s] %3d%%${RESET} | ETA: %02d:%02d" \
      "$BAR" "$SPACE" "$PERCENT" "$ETA_MIN" "$ETA_SEC"
    fi
  done
  echo ""
}

run_ffmpeg_pass () {
  PASS=$1
  EXTRA=$2

  ffmpeg -y -i "$INPUT" \
  -vf "$SCALE" \
  -c:v libx264 -preset veryfast -b:v ${VIDEO_K}k \
  -pass $PASS $EXTRA \
  -progress pipe:1 -nostats 2>/dev/null | progress_bar
}

try_encode () {
  SCALE=$1
  LABEL=$2

  echo ""
  echo "🚀 Tentando: $LABEL ($SCALE)"

  BITRATE=$((TARGET_BITS / DURATION))
  VIDEO=$((BITRATE - AUDIO))
  VIDEO_K=$((VIDEO / 1000))

  if [[ "$VIDEO_K" -le 0 ]]; then
    echo "❌ Bitrate inválido"
    return 1
  fi

  echo "🎯 Bitrate vídeo: ${VIDEO_K}k"

  echo "▶ Passo 1/2"
  run_ffmpeg_pass 1 "-an -f null /dev/null"

  echo "▶ Passo 2/2"
  run_ffmpeg_pass 2 "-c:a aac -b:a 128k \"$OUTPUT\""

  SIZE_MB=$(du -m "$OUTPUT" | cut -f1)

  echo "📦 Tamanho final: ${SIZE_MB} MB"

  if [[ "$SIZE_MB" -le "$TARGET_MB" ]]; then
    echo "✅ Sucesso com $LABEL"
    return 0
  else
    echo "⚠ Ainda grande, tentando menor..."
    return 1
  fi
}

if try_encode "scale=-2:-2" "Original"; then exit 0; fi
if try_encode "scale=1280:-2" "720p"; then exit 0; fi
if try_encode "scale=854:-2" "480p"; then exit 0; fi

echo "❌ Não foi possível atingir o tamanho desejado"
exit 1
