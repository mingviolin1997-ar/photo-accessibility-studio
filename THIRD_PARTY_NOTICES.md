# Third-party notices

This project downloads or links to the following components without relicensing them:

- Ollama, MIT License: <https://github.com/ollama/ollama>
- ExifTool by Phil Harvey, Perl Artistic License or GPL: <https://exiftool.org/>
- LiteRT-LM by Google AI Edge, Apache License 2.0: <https://github.com/google-ai-edge/LiteRT-LM>
- Qwen3.5-4B base model, Apache License 2.0: <https://huggingface.co/Qwen/Qwen3.5-4B>
- Qwen3.5-4B LiteRT multimodal conversion used by the Android test build:
  <https://huggingface.co/trevon/Qwen3.5-4B-LiteRT>
- Gemma 4 E2B/E4B model weights and documentation, Apache License 2.0:
  <https://ai.google.dev/gemma/docs/core>
- Gemma 3n E2B/E4B model weights are governed by Google's Gemma terms:
  <https://ai.google.dev/gemma/terms>
- Ollama-packaged Gemma download tags:
  <https://ollama.com/library/gemma4> and <https://ollama.com/library/gemma3n>

The Android downloader pins the converted model revision and SHA-256. The macOS downloader pins the Ollama and ExifTool archives and verifies their SHA-256 values before installation.
