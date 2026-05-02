#!/usr/bin/env python3
import argparse
import json
import sys

from mlx_whisper import transcribe


def main() -> int:
    parser = argparse.ArgumentParser(description="Transcribe one local audio file with mlx-whisper.")
    parser.add_argument("--audio", required=True)
    parser.add_argument("--model", required=True)
    args = parser.parse_args()

    result = transcribe(args.audio, path_or_hf_repo=args.model)
    text = (result.get("text") or "").strip()
    segments = []
    for segment in result.get("segments") or []:
        segments.append(
            {
                "start": segment.get("start"),
                "end": segment.get("end"),
                "text": (segment.get("text") or "").strip(),
            }
        )

    print(
        json.dumps(
            {
                "language": result.get("language"),
                "text": text,
                "segments": segments,
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
