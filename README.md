# Image-Studio Codex Skill

This folder wraps the Image-Studio image generation capability as a Codex-callable local skill. It supports OpenAI-compatible Images APIs and restricted Running Hub gpt-image-2 standard-model APIs.

It does not launch the Image-Studio desktop app. It only uses command-line image generation and editing capability through `skills/image-studio/bin/gptcodex-image`.

## Install

```bash
bash skills/image-studio/scripts/install.sh
```

## Configure

Copy the example env file:

```bash
cp skills/image-studio/config/image-studio.example.env skills/image-studio/config/image-studio.env
```

The private `skills/image-studio/config/image-studio.env` file is the final place to put provider credentials. Do not put real keys in `config/image-studio.example.env`; that file is only a template for the open-source repo.

Edit:

```bash
skills/image-studio/config/image-studio.env
```

Common required settings:

```env
IMAGE_STUDIO_PROVIDER=auto
IMAGE_STUDIO_BASE_URL=
IMAGE_STUDIO_API_KEY=
IMAGE_STUDIO_IMAGE_MODEL=
IMAGE_STUDIO_OUTPUT_DIR=
```

### OpenAI-Compatible Relay / 中转站

For a relay API key, fill the relay block in `skills/image-studio/config/image-studio.env`:

```env
IMAGE_STUDIO_PROVIDER=openai
IMAGE_STUDIO_BASE_URL=https://relay.example.com/v1
IMAGE_STUDIO_API_KEY=replace_with_your_relay_api_key
IMAGE_STUDIO_IMAGE_MODEL=gpt-image-1
IMAGE_STUDIO_DEFAULT_SIZE=1024x1024
IMAGE_STUDIO_DEFAULT_QUALITY=high
IMAGE_STUDIO_TIMEOUT_SECONDS=300
IMAGE_STUDIO_MAX_RETRIES=2
```

Replace `IMAGE_STUDIO_BASE_URL` with the relay service's OpenAI-compatible base URL, replace `IMAGE_STUDIO_API_KEY` with the relay key, and set `IMAGE_STUDIO_IMAGE_MODEL` to a model the relay actually exposes, such as `gpt-image-1` or the relay's documented image model. `IMAGE_STUDIO_OUTPUT_DIR` controls where generated images, metadata, raw responses, and logs are saved.

### Running Hub

For a Running Hub API key, fill this block in `skills/image-studio/config/image-studio.env`:

```env
IMAGE_STUDIO_PROVIDER=runninghub
IMAGE_STUDIO_BASE_URL=https://www.runninghub.cn
IMAGE_STUDIO_API_KEY=replace_with_your_runninghub_api_key
IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL=/rhart-image-g-2-official/text-to-image
IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL=/rhart-image-g-2/image-to-image
IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO=16:9
IMAGE_STUDIO_RUNNINGHUB_RESOLUTION=1k
```

In Running Hub mode, `RUNNINGHUB_API_KEY` is also accepted when `IMAGE_STUDIO_API_KEY` is unset or still uses an example placeholder.

## Check Environment

```bash
bash skills/image-studio/scripts/check-env.sh
```

## Text-to-Image

```bash
bash skills/image-studio/scripts/generate-image.sh \
  --prompt "A clean architectural concept sketch of a small public plaza light installation" \
  --size "1024x1024" \
  --quality "high"
```

## Image Editing

```bash
bash skills/image-studio/scripts/edit-image.sh \
  --prompt "Convert this image into a clean architectural concept diagram" \
  --input "./input/source.png"
```

Running Hub mode is restricted to gpt-image-2 endpoints. Image editing uses `/rhart-image-g-2/image-to-image` and requires at least one `--input` image:

```bash
bash skills/image-studio/scripts/edit-image.sh \
  --prompt "Keep the source composition and turn it into a polished product render" \
  --input "./input/source.png" \
  --aspect-ratio "16:9" \
  --resolution "1k"
```

## Batch Editing

```bash
bash skills/image-studio/scripts/batch-edit-image.sh \
  --prompt "Convert all images into white-background product presentation images" \
  --input-dir "./input/images"
```

## Outputs

Images:

```text
outputs/images/
```

Metadata:

```text
outputs/metadata/
```

Raw responses:

```text
outputs/raw/
```

Logs:

```text
outputs/logs/
```

## Notes

Do not commit API keys. Do not commit `.env` files. Do not overwrite user input files. Do not modify source images in place. Always save new outputs.

Image-Studio is licensed upstream under AGPL-3.0 at the time this wrapper was created. Preserve upstream licenses and author attribution when using or modifying the upstream repository.
