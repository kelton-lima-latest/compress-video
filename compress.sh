#!/bin/bash

set -e

INPUT="$1"
OUTPUT="${2:-saida.mp4}"
TARGET_MB=200
MARGIN_MB=5   # margem de segurança

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

# duração (inteiro)
DURATION=$(ffprobe -v error -show_entries format=duration \
-of default=noprint_wrappers=1:nokey=1 "$INPUT")

DURATION=${DURATION%.*}

if [[ -z "$DURATION" || "$DURATION" -le 0 ]]; then
  echo "Erro ao obter duração"
  exit 1
fi

echo "⏱ Duração: ${DURATION}s"

# resolução original
RES=$(ffprobe -v error -select_streams v:0 \
-show_entries stream=width,height \
-of csv=s=x:p=0 "$INPUT")

echo "📺 Resolução original: $RES"

# cálculo base
TARGET_BITS=$(( (TARGET_MB - MARGIN_MB) * 1024 * 1024 * 8 ))
AUDIO=128000

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

  ffmpeg -y -loglevel error -i "$INPUT" \
  -vf "$SCALE" \
  -c:v libx264 -preset veryfast -b:v ${VIDEO_K}k \
  -pass 1 -an -f null /dev/null

  ffmpeg -y -loglevel error -i "$INPUT" \
  -vf "$SCALE" \
  -c:v libx264 -preset veryfast -b:v ${VIDEO_K}k \
  -pass 2 -c:a aac -b:a 128k \
  "$OUTPUT"

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

# tentativa progressiva
if try_encode "scale=-2:-2" "Original"; then exit 0; fi
if try_encode "scale=1280:-2" "720p"; then exit 0; fi
if try_encode "scale=854:-2" "480p"; then exit 0; fi

echo "❌ Não foi possível atingir o tamanho desejado"
exit 1
