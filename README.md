# Prompt Jockey SMS -> Collider Bridge
This service accepts inbound SMS webhook calls and creates a new node in Collider for each text prompt.

## What this gives you
A user can text Prompt Jockey, and that text appears as a node in Collider.

## 2-minute demo checklist
Use this for the fastest end-to-end test with a real phone.

1. Start the bridge:

```bash
source .venv/bin/activate
uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

2. Start ngrok in another terminal:

```bash
ngrok http 8000
```

3. In Twilio, set your number/messaging webhook:
- `A message comes in`: `https://<your-ngrok-domain>/webhooks/sms`
- Method: `HTTP POST`
- where <your-ngrok-domain> comes from the terminal output after you start ngrok. note that 
- this changes each time you restart ngrok, and twilio needs to be updated with the new one.

4. Open the app:

```bash
open "runtime/Prompt Jockey Request Line.app"
```

5. Text your Twilio number from your phone.

Expected result: one new prompt request node appears in Collider for each SMS.

## Quick start
1. Create and activate a Python environment (recommended Python 3.12).
2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Create `.env` from the sample:

```bash
cp .env.example .env
```

4. Fill in at least:
- `COLLIDER_TRANSPORT`

If `COLLIDER_TRANSPORT=http`:
- `COLLIDER_BASE_URL`

Optional:
- `COLLIDER_API_TOKEN` (only if your Collider instance requires auth)

5. Run the API:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

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

## Twilio + ngrok setup (real phone SMS)
Use this when you want anyone to text a Twilio number and have prompts appear in Collider.

1. Install and configure ngrok (one-time):

```bash
brew install ngrok/ngrok/ngrok
ngrok config add-authtoken <YOUR_NGROK_AUTHTOKEN>
```

2. Configure the bridge `.env` for desktop Collider defaults mode:
- `COLLIDER_TRANSPORT=defaults`
- `COLLIDER_BUNDLE_ID=com.google.promptjockeyrequestline`
- `COLLIDER_PROMPT_KEY=Collider_Prompt`
- Leave `WEBHOOK_SHARED_SECRET` empty for Twilio tests.

3. Start the bridge server:

```bash
uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

4. In another terminal, start ngrok:

```bash
ngrok http 8000
```

5. Copy the HTTPS forwarding URL from ngrok, then append `/webhooks/sms`.
Example:
- `https://abcd-1234.ngrok-free.app/webhooks/sms`

6. In Twilio Console, buy or select an SMS-capable number and set:
- `A message comes in` webhook URL: your ngrok URL with `/webhooks/sms`
- Method: `HTTP POST`

7. Open the app and test:

```bash
open "runtime/Prompt Jockey Request Line.app"
```

Then text the Twilio number from your phone. Each SMS should create one prompt request node.

### Twilio notes
- Twilio trial accounts restrict who can message your number (verified senders only).
- Paid Twilio numbers allow public inbound SMS.
- Free ngrok URLs change when restarted; update Twilio webhook URL each time unless you use a reserved ngrok domain.
