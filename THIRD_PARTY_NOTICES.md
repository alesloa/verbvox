# Third-party notices

## whisper.cpp

VerbVox.app bundles a `whisper-server` binary built from
[whisper.cpp](https://github.com/ggml-org/whisper.cpp), copyright (c) 2023-2026
The ggml authors, licensed under MIT. `app/scripts/whisper-engine.sh` builds it
from tag `v1.9.5` (commit `d1be6fde11ac6e0407606b4e42fe72d34add8037`) and copies
the license into the app as `Contents/Resources/LICENSE-whisper.cpp.txt`.

## Warm-up clip

`app/Resources/warmup.wav` is a synthetic sentence generated with the speech
synthesizer built into Windows (`System.Speech`). The engine transcribes it to
check and time each model.

## Whisper models

The built-in engine downloads ggml-format Whisper models from
[ggerganov/whisper.cpp on Hugging Face](https://huggingface.co/ggerganov/whisper.cpp)
on first launch. The models are not stored in this repository. The repository is
licensed under MIT, and the original Whisper weights are released by
[OpenAI](https://github.com/openai/whisper) under MIT.
