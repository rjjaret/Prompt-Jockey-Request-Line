# Prompt Jockey SMS -> Collider Bridge
This service accepts inbound SMS webhook calls and creates a new node in Collider for each text prompt.

Demo video:
https://vimeo.com/1205849400?fl=ip&fe=ec

## What this gives you
A user can text Prompt Jockey, and that text appears as a node in Collider.

## Quick Start (Minimal)
Use this path for the fastest working setup.

1. Activate your Python environment:

```bash
source .venv/bin/activate
```

2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Set transport mode for desktop app integration:

```bash
export COLLIDER_TRANSPORT=defaults
```

4. Start the bridge API:

```bash
uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

5. Start ngrok in another terminal:

```bash
ngrok http 8000
```

6. In Twilio (or another sms forwarding service - I rented a number in Twilio), set your number webhook from the Forwarding url in the ngrok output:
- `A message comes in`: `https://<your-ngrok-domain>/webhooks/sms`
- Method: `HTTP POST`
  Note that this can change when you restart ngrok, in which case the forwarding service needs to be updated.


7. Open the app in another terminal window:
```bash
./scripts/ensure_prebuilt_app.sh
open "prebuilt/Prompt Jockey Request Line.app"
```

Then text your Twilio number. Each SMS should create one prompt request node.

---

## Other Operations and Configuration

### Optional `.env` file
You do not need a `.env` file if you export vars in your shell.

If you prefer `.env`:

```bash
cp .env.example .env
```

For desktop defaults mode, the only required setting is:

```dotenv
COLLIDER_TRANSPORT=defaults
```


### HTTP mode (instead of desktop defaults mode)
Use this if you want to send prompts to a Collider HTTP API.

Required:

```dotenv
COLLIDER_TRANSPORT=http
COLLIDER_BASE_URL=http://localhost:8080
```


Optional:
- `COLLIDER_API_TOKEN`
- `COLLIDER_CREATE_NODE_PATH` (default `/api/nodes`)
- `COLLIDER_NODE_TYPE` (default `prompt`)

### Twilio + ngrok notes
- Free ngrok URLs usually change on restart, so update your Twilio webhook URL when that happens.
- Twilio trial accounts only accept messages from verified senders.
- Paid Twilio numbers allow broader inbound SMS.

## Webhook endpoint
- Method: `POST`
- URL: `/webhooks/sms`
- Content type: `application/x-www-form-urlencoded`
- Expected fields (Twilio-compatible):
- `Body`: prompt text
- `From`: sender phone number
- `MessageSid`: unique SMS ID

### Optional signature validation
If you set `WEBHOOK_SHARED_SECRET`, each request must include:
- Header: `X-Webhook-Signature`
- Value: `hex(hmac_sha256(raw_request_body, WEBHOOK_SHARED_SECRET))`

If this header is missing or invalid, the request is rejected.

## Collider transport modes
This bridge supports two Collider targets:

1. `http` mode
- Sends `POST` requests to Collider (for API-backed deployments).
- Uses `COLLIDER_BASE_URL`, `COLLIDER_CREATE_NODE_PATH`, `COLLIDER_NODE_TYPE`.

2. `defaults` mode (macOS desktop app)
- Writes prompt text into macOS defaults for the Collider app.
- Uses `COLLIDER_BUNDLE_ID` and `COLLIDER_PROMPT_KEY` (default `Collider_Prompt`).
- For this project, use a dedicated Collider variant named `Prompt Jockey Request Line` so EmotionalMagenta remains untouched.
- No localhost API port is required.

## Health check
`GET /health` returns:
- `ok`
- `collider_configured`

## Collider payload shape
In `http` mode, each SMS creates a request to Collider:

```json
{
  "type": "prompt",
  "title": "SMS: <first line trimmed to 80 chars>",
  "content": "<full SMS body>",
  "metadata": {
    "source": "prompt-jockey-sms",
    "sender": "<From>",
    "message_id": "<MessageSid>"
  }
}
```


You can change:
- `COLLIDER_CREATE_NODE_PATH` (default `/api/nodes`)
- `COLLIDER_NODE_TYPE` (default `prompt`)

In `defaults` mode, each SMS writes:
- `defaults write <COLLIDER_BUNDLE_ID> <COLLIDER_PROMPT_KEY> "<SMS body>"`

In addition, each SMS is always appended to `Collider_PromptHistory` and the app index `Collider_HistoryIndex` is advanced to the latest entry. This maps each incoming text to its own history/node item in the dedicated variant.
