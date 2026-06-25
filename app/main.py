import hmac
import os
from hashlib import sha256
from urllib.parse import parse_qs

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

from app.collider import ColliderClient

load_dotenv()

app = FastAPI(title="Prompt Jockey SMS -> Collider Bridge")
collider = ColliderClient()


def _verify_optional_shared_secret(raw_body: bytes, signature: str | None) -> None:
    secret = os.getenv("WEBHOOK_SHARED_SECRET")
    if not secret:
        return
    if not signature:
        raise HTTPException(status_code=401, detail="Missing webhook signature")

    digest = hmac.new(secret.encode("utf-8"), raw_body, sha256).hexdigest()
    if not hmac.compare_digest(digest, signature):
        raise HTTPException(status_code=401, detail="Invalid webhook signature")


@app.get("/health")
async def health() -> dict[str, object]:
    return {
        "ok": True,
        "collider_configured": collider.enabled,
    }


@app.post("/webhooks/sms")
async def receive_sms(
    request: Request,
    x_webhook_signature: str | None = Header(default=None, alias="X-Webhook-Signature"),
) -> JSONResponse:
    # Read and verify raw payload once, then parse fields from it.
    raw_body = await request.body()
    _verify_optional_shared_secret(raw_body, x_webhook_signature)

    parsed = parse_qs(raw_body.decode("utf-8"), keep_blank_values=True)
    body = parsed.get("Body", [""])[0]
    from_number = parsed.get("From", [""])[0]
    message_sid = parsed.get("MessageSid", [""])[0]

    prompt_text = body.strip()
    if not prompt_text:
        raise HTTPException(status_code=400, detail="SMS body is empty")

    try:
        result = await collider.create_prompt_node(
            prompt_text=prompt_text,
            sender=from_number or None,
            message_id=message_sid or None,
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Failed to create Collider node: {exc}") from exc

    return JSONResponse(
        status_code=200,
        content={
            "ok": True,
            "source": "sms",
            "sender": from_number,
            "message_sid": message_sid,
            "collider_result": result,
        },
    )
