# Running Hub Provider Reference

Use this reference only when debugging Running Hub behavior or adding support for more Running Hub standard-model SKUs.

## Provider Config

Use the setup wizard for normal installation:

```bash
bash skills/image-studio/scripts/configure-env.sh
```

The final API key location is the private file `skills/image-studio/config/image-studio.env`. Do not put real keys in `config/image-studio.example.env`.

Set:

```env
IMAGE_STUDIO_PROVIDER=runninghub
IMAGE_STUDIO_BASE_URL=https://www.runninghub.cn
IMAGE_STUDIO_API_KEY=RUNNING_HUB_API_KEY_HERE
IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL=/rhart-image-g-2-official/text-to-image
IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL=/rhart-image-g-2/image-to-image
```

`RUNNINGHUB_API_KEY` is also accepted when `IMAGE_STUDIO_API_KEY` is unset or still has an example placeholder.

`IMAGE_STUDIO_BASE_URL` should normally be the site origin. If a user provides `/openapi/v2`, the wrapper trims it before constructing API endpoints.

Running Hub use is deliberately restricted to two gpt-image-2 endpoints:

- Text-to-image: `/rhart-image-g-2-official/text-to-image`
- Image-to-image: `/rhart-image-g-2/image-to-image`

The wrapper rejects any Running Hub SKU whose detail returns a different `rhEndpoint`. `generate` mode must use the text-to-image endpoint, and `edit` mode must use the image-to-image endpoint.

## API Pattern

Fetch SKU detail:

```http
POST https://www.runninghub.cn/api/sku/detail
Content-Type: application/json

{"id":"2046503667076751361"}
```

The wrapper reads `data.rhEndpoint` and parses `data.inputConfigJson` to map fields.

Upload local images before submitting image fields:

```http
POST https://www.runninghub.cn/openapi/v2/media/upload/binary
Authorization: Bearer RUNNING_HUB_API_KEY
Content-Type: multipart/form-data
```

The multipart field name is `file`. Use `data.download_url` from the response as the image URL.

Submit the standard-model task:

```http
POST https://www.runninghub.cn/openapi/v2/<rhEndpoint>
Authorization: Bearer RUNNING_HUB_API_KEY
Content-Type: application/json
```

For image-to-image, `rhEndpoint` is `/rhart-image-g-2/image-to-image`, and the payload fields are:

```json
{
  "prompt": "edit instructions",
  "imageUrls": ["uploaded image URL"],
  "aspectRatio": "16:9",
  "resolution": "1k"
}
```

For text-to-image, `rhEndpoint` is `/rhart-image-g-2-official/text-to-image`; use the same payload minus `imageUrls`.

Poll the task:

```http
POST https://www.runninghub.cn/openapi/v2/query
Authorization: Bearer RUNNING_HUB_API_KEY
Content-Type: application/json

{"taskId":"TASK_ID"}
```

Keep polling while status is `RUNNING`, `QUEUED`, `PENDING`, or `WAITING`. On `SUCCESS`, download the first URL from `results[].url`, `results[].fileUrl`, or `results[].download_url`.
