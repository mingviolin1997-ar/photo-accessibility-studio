# Third-party notices

This project downloads or links to the following components without relicensing them:

- Ollama, MIT License: <https://github.com/ollama/ollama>
- MLX-VLM, MIT License: <https://github.com/Blaizzy/mlx-vlm>
- MLX by Apple, MIT License: <https://github.com/ml-explore/mlx>
- uv by Astral, Apache License 2.0 or MIT License: <https://github.com/astral-sh/uv>
- ExifTool by Phil Harvey, Perl Artistic License or GPL: <https://exiftool.org/>
- LiteRT-LM by Google AI Edge, Apache License 2.0: <https://github.com/google-ai-edge/LiteRT-LM>
- Qwen3.5-4B base model, Apache License 2.0: <https://huggingface.co/Qwen/Qwen3.5-4B>
- Qwen3.5-4B 4-bit MLX conversion, Apache License 2.0:
  <https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit>
- Qwen3.5-4B LiteRT multimodal conversion used by the Android test build:
  <https://huggingface.co/trevon/Qwen3.5-4B-LiteRT>
- Gemma 4 E2B/E4B model weights and documentation, Apache License 2.0:
  <https://ai.google.dev/gemma/docs/core>
- Gemma 3n E2B/E4B model weights are governed by Google's Gemma terms:
  <https://ai.google.dev/gemma/terms>
- Ollama-packaged Gemma download tags:
  <https://ollama.com/library/gemma4> and <https://ollama.com/library/gemma3n>
- MLX-community Gemma model collections:
  <https://huggingface.co/collections/mlx-community/gemma-4> and
  <https://huggingface.co/collections/mlx-community/gemma-3n>

The Android downloader pins the converted model revision and SHA-256. The macOS downloader pins the Ollama, ExifTool, uv, and MLX-VLM versions. Downloaded archives are checked against their SHA-256 values; Hugging Face Hub verifies MLX model files during download.
