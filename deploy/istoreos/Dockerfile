FROM node:24-bookworm-slim

# devices.py talks to /var/run/usbmuxd over a unix socket; prepare-remote.mjs also needs python3.
# tesseract plus Pillow stand in for build/ocr, which is native/ocr.swift on macOS and links
# Vision. Without them a screen the accessibility tree cannot read has no other source.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-pil ca-certificates \
      tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-eng \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV POKI_MCP_STATE_DIR=/state
EXPOSE 47825
