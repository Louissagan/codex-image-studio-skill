---
name: image-studio
description: Generate, edit, transform, or batch-process images through a local Image-Studio CLI wrapper with OpenAI-compatible Images APIs or restricted Running Hub gpt-image-2 standard-model APIs. Use when Codex needs actual image output for text-to-image generation, image-to-image transformation, image editing with optional masks, multi-reference image generation, architectural/product/brand visual exploration, or batch image style conversion with structured saved images, logs, raw responses, and metadata.
---

# Image Studio Skill

## Purpose

Use this skill when the user asks to generate, edit, transform, or batch-process images through the local Image-Studio CLI wrapper.

This skill provides a stable command-line interface for text-to-image, image-to-image, image editing, multi-reference image generation, and batch image editing tasks. It does not launch the Image-Studio desktop app or depend on the Wails UI.

The wrapper supports OpenAI-compatible Images APIs and Running Hub gpt-image-2 standard-model APIs. Prefer `IMAGE_STUDIO_PROVIDER=runninghub` for Running Hub; `auto` also detects Running Hub when the base URL contains `runninghub`.

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

## Provider Configuration

The final place to fill any provider key is the private file `skills/image-studio/config/image-studio.env`. Never put a real key in `config/image-studio.example.env` or in this skill documentation.

For an OpenAI-compatible relay provider (中转站), configure all of these in `image-studio.env`:

```env
IMAGE_STUDIO_PROVIDER=openai
IMAGE_STUDIO_BASE_URL=https://relay.example.com/v1
IMAGE_STUDIO_API_KEY=RELAY_API_KEY_HERE
IMAGE_STUDIO_IMAGE_MODEL=gpt-image-1
IMAGE_STUDIO_DEFAULT_SIZE=1024x1024
IMAGE_STUDIO_DEFAULT_QUALITY=high
IMAGE_STUDIO_TIMEOUT_SECONDS=300
IMAGE_STUDIO_MAX_RETRIES=2
```

Use the relay service's actual `BASE_URL`, `API_KEY`, and supported image `MODEL`. The wrapper treats `openai` as an OpenAI-compatible Images API provider and appends `/v1` when the base URL omits it.

## Running Hub Setup

Use Running Hub when OpenAI-compatible relay image generation is unstable or when the user gives a Running Hub API detail/SKU page. Configure the private env file like this:

```env
IMAGE_STUDIO_PROVIDER=runninghub
IMAGE_STUDIO_BASE_URL=https://www.runninghub.cn
IMAGE_STUDIO_API_KEY=RUNNING_HUB_API_KEY_HERE
IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL=/rhart-image-g-2-official/text-to-image
IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL=/rhart-image-g-2/image-to-image
IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO=16:9
IMAGE_STUDIO_RUNNINGHUB_RESOLUTION=1k
IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS=1800
```

`RUNNINGHUB_API_KEY` is also accepted in Running Hub mode when `IMAGE_STUDIO_API_KEY` is unset or still uses an example placeholder.

Running Hub is intentionally restricted to gpt-image-2 endpoints: `generate-image.sh` uses `/rhart-image-g-2-official/text-to-image`, while `edit-image.sh` and `batch-edit-image.sh` use `/rhart-image-g-2/image-to-image`. Do not use other Running Hub endpoints or SKUs for this skill. The edit endpoint is image-to-image: pass at least one `--input` image with `edit-image.sh` or `batch-edit-image.sh`. Override Running Hub fields with `--aspect-ratio` and `--resolution` when needed.

For Running Hub request/response details, read `references/runninghub.md` only when debugging provider behavior or adding more SKU mappings.

## Text-to-Image

Use `generate-image.sh` for prompt-only generation:

```bash
bash skills/image-studio/scripts/generate-image.sh \
  --prompt "PROMPT_HERE" \
  --size "1024x1024" \
  --quality "high" \
  --output-dir "./skills/image-studio/outputs"
```

Supported parameters: `--prompt`, `--size`, `--quality`, `--model`, `--output-dir`, `--metadata`, `--raw`, `--aspect-ratio`, `--resolution`.

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

Supported parameters: `--prompt`, `--input`, `--mask`, `--size`, `--quality`, `--model`, `--output-dir`, `--metadata`, `--raw`, `--aspect-ratio`, `--resolution`.

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

Every metadata JSON includes `task_id`, `provider`, `mode`, `prompt`, `input_images`, `mask`, `model`, `size`, `quality`, `base_url`, `output_images`, `raw_response_path`, `log_path`, `created_at`, `status`, and `error`. Running Hub outputs may also include `upstream_task_id` and `output_url`.

## Error Handling

If generation fails, save any available raw response, save metadata with `status: failed`, save a log file, and return a clear error message. Common failures to identify: invalid API key (`401`/`403`), missing model (`404`/`model_not_found`), timeout (`504`/`524`/`timeout`), no returned image, missing input files, and unwritable output directories.

## Policy

Never commit `.env` files, never overwrite existing images, never delete or modify source images in place, and always return the image path, metadata path, and raw response path so Codex can reuse them in later steps.

For architectural concept images, include subject, scene, composition, visual style, materials, lighting, camera angle, output purpose, and constraints in the prompt.
