# Third-party notices

This project downloads or links to the following components without relicensing them:

- Ollama, MIT License: <https://github.com/ollama/ollama>
- ExifTool by Phil Harvey, Perl Artistic License or GPL: <https://exiftool.org/>
- LiteRT-LM by Google AI Edge, Apache License 2.0: <https://github.com/google-ai-edge/LiteRT-LM>
- Qwen3.5-4B base model, Apache License 2.0: <https://huggingface.co/Qwen/Qwen3.5-4B>
- Qwen3.5-4B LiteRT multimodal conversion used by the Android test build:
  <https://huggingface.co/trevon/Qwen3.5-4B-LiteRT>
- Gemma 4 E2B and E4B LiteRT-LM conversions, Apache License 2.0:
  <https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm>
  and <https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm>
- Gemma 3n E2B and E4B LiteRT-LM models, Gemma Terms of Use:
  <https://huggingface.co/google/gemma-3n-E2B-it-litert-lm>
  and <https://huggingface.co/google/gemma-3n-E4B-it-litert-lm>

The Android downloader pins every converted model revision, byte count, and SHA-256. The macOS downloader pins its runtime and model inputs and verifies their integrity before installation.
