# Image-Studio Codex Skill

This folder wraps the Image-Studio image generation capability as a Codex-callable local skill.

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

The private `skills/image-studio/config/image-studio.env` file is the place to put this skill's own API base URL and API key.

Edit:

```bash
skills/image-studio/config/image-studio.env
```

Required:

```env
IMAGE_STUDIO_BASE_URL=
IMAGE_STUDIO_API_KEY=
IMAGE_STUDIO_IMAGE_MODEL=
IMAGE_STUDIO_OUTPUT_DIR=
```

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
