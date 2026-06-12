---
name: codex-image-studio-skill
description: Generate, edit, transform, or batch-process images from Codex through a local Image-Studio CLI wrapper. Use when Codex needs a public, installable skill for text-to-image generation, image-to-image transformation, image editing with optional masks, multi-reference image generation, architectural/product/brand visual exploration, or batch image style conversion with structured saved images, logs, raw responses, and metadata.
---

# Image Studio Skill

## Purpose

Use this skill when the user asks to generate, edit, transform, or batch-process images through the local Image-Studio CLI wrapper.

This skill provides a stable command-line interface for text-to-image, image-to-image, image editing, multi-reference image generation, and batch image editing tasks. It does not launch the Image-Studio desktop app or depend on the Wails UI.

## Required Setup

Install or refresh the local CLI wrapper before first use:

```bash
bash skills/image-studio/scripts/install.sh
```

Create a private env file from the example, then fill in the API key and any upstream overrides:

```bash
cp skills/image-studio/config/image-studio.example.env skills/image-studio/config/image-studio.env
bash skills/image-studio/scripts/check-env.sh
```

Never hardcode API keys. Prefer environment variables; the scripts also load `skills/image-studio/config/image-studio.env` when it exists.

## Text-to-Image

Use `generate-image.sh` for prompt-only generation:

```bash
bash skills/image-studio/scripts/generate-image.sh \
  --prompt "PROMPT_HERE" \
  --size "1024x1024" \
  --quality "high" \
  --output-dir "./skills/image-studio/outputs"
```

Supported parameters: `--prompt`, `--size`, `--quality`, `--model`, `--output-dir`, `--metadata`, `--raw`.

## Image Editing

Use `edit-image.sh` for image-to-image, image edits, and optional masked edits:

```bash
bash skills/image-studio/scripts/edit-image.sh \
  --prompt "PROMPT_HERE" \
  --input "./input/source.png" \
  --size "1024x1024" \
  --quality "high" \
  --output-dir "./skills/image-studio/outputs"
```

Supported parameters: `--prompt`, `--input`, `--mask`, `--size`, `--quality`, `--model`, `--output-dir`, `--metadata`, `--raw`.

For multi-reference edits, pass `--input` more than once if the installed wrapper supports it. If the upstream binary only supports a single input image, split the task into one edit per source or update the wrapper through `install.sh`.

## Batch Editing

Use `batch-edit-image.sh` for directories of `.png`, `.jpg`, `.jpeg`, or `.webp` files:

```bash
bash skills/image-studio/scripts/batch-edit-image.sh \
  --prompt "PROMPT_HERE" \
  --input-dir "./input/images" \
  --output-dir "./skills/image-studio/outputs/batch"
```

The batch script continues after per-image failures, writes each image's metadata and raw response separately, and prints success and failure counts.

## Output Rules

Each invocation creates a unique task id in `YYYYMMDD-HHMMSS-random` form and writes structured artifacts under the selected output directory:

- Images: `outputs/images/`
- Metadata: `outputs/metadata/`
- Raw responses: `outputs/raw/`
- Logs: `outputs/logs/`

Every metadata JSON includes `task_id`, `mode`, `prompt`, `input_images`, `mask`, `model`, `size`, `quality`, `base_url`, `output_images`, `raw_response_path`, `log_path`, `created_at`, `status`, and `error`.

## Error Handling

If generation fails, save any available raw response, save metadata with `status: failed`, save a log file, and return a clear error message. Common failures to identify: invalid API key (`401`/`403`), missing model (`404`/`model_not_found`), timeout (`504`/`524`/`timeout`), no returned image, missing input files, and unwritable output directories.

## Policy

Never commit `.env` files, never overwrite existing images, never delete or modify source images in place, and always return the image path, metadata path, and raw response path so Codex can reuse them in later steps.

For architectural concept images, include subject, scene, composition, visual style, materials, lighting, camera angle, output purpose, and constraints in the prompt.
