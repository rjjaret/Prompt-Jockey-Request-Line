import os
import subprocess
from typing import Any

import httpx


class ColliderClient:
    def __init__(self) -> None:
        self.transport = os.getenv("COLLIDER_TRANSPORT", "http").strip().lower()
        self.base_url = os.getenv("COLLIDER_BASE_URL", "").rstrip("/")
        self.api_token = os.getenv("COLLIDER_API_TOKEN", "")
        self.create_node_path = os.getenv("COLLIDER_CREATE_NODE_PATH", "/api/nodes")
        self.node_type = os.getenv("COLLIDER_NODE_TYPE", "prompt")
        self.bundle_id = os.getenv("COLLIDER_BUNDLE_ID", "com.google.promptjockeyrequestline")
        self.prompt_key = os.getenv("COLLIDER_PROMPT_KEY", "Collider_Prompt")
        self.history_key = "Collider_PromptHistory"
        self.history_index_key = "Collider_HistoryIndex"

    @property
    def enabled(self) -> bool:
        if self.transport == "defaults":
            return bool(self.bundle_id and self.prompt_key)
        return bool(self.base_url)

    async def create_prompt_node(
        self,
        prompt_text: str,
        sender: str | None = None,
        message_id: str | None = None,
    ) -> dict[str, Any]:
        if not self.enabled:
            if self.transport == "defaults":
                raise RuntimeError("Collider defaults mode is not configured. Set COLLIDER_BUNDLE_ID and COLLIDER_PROMPT_KEY.")
            raise RuntimeError("Collider HTTP mode is not configured. Set COLLIDER_BASE_URL.")

        if self.transport == "defaults":
            completed = subprocess.run(
                ["defaults", "write", self.bundle_id, self.prompt_key, prompt_text],
                check=False,
                capture_output=True,
                text=True,
            )
            if completed.returncode != 0:
                stderr = completed.stderr.strip() or "defaults write failed"
                raise RuntimeError(stderr)

            append_result = subprocess.run(
                ["defaults", "write", self.bundle_id, self.history_key, "-array-add", prompt_text],
                check=False,
                capture_output=True,
                text=True,
            )
            if append_result.returncode != 0:
                stderr = append_result.stderr.strip() or "defaults array-add failed"
                raise RuntimeError(stderr)

            index_expr = (
                f"d=defaults; b={self.bundle_id!r}; k={self.history_key!r}; "
                "n=$($d read \"$b\" \"$k\" 2>/dev/null | "
                "awk 'BEGIN{c=0} /^[[:space:]]*\".*\",?$/ {c++} END{print c}'); "
                "if [ -z \"$n\" ] || [ \"$n\" -le 0 ]; then n=1; fi; "
                f"$d write \"$b\" {self.history_index_key!r} -int $((n-1))"
            )
            index_result = subprocess.run(
                ["/bin/zsh", "-lc", index_expr],
                check=False,
                capture_output=True,
                text=True,
            )
            if index_result.returncode != 0:
                stderr = index_result.stderr.strip() or "defaults history index update failed"
                raise RuntimeError(stderr)

            return {
                "ok": True,
                "transport": "defaults",
                "bundle_id": self.bundle_id,
                "prompt_key": self.prompt_key,
                "history_appended": True,
            }

        url = f"{self.base_url}{self.create_node_path}"

        title_base = prompt_text.strip().splitlines()[0][:80] if prompt_text.strip() else "SMS Prompt"
        payload: dict[str, Any] = {
            "type": self.node_type,
            "title": f"SMS: {title_base}",
            "content": prompt_text,
            "metadata": {
                "source": "prompt-jockey-sms",
                "sender": sender,
                "message_id": message_id,
            },
        }

        headers = {"Content-Type": "application/json"}
        if self.api_token:
            headers["Authorization"] = f"Bearer {self.api_token}"

        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.post(url, json=payload, headers=headers)
            response.raise_for_status()
            return response.json() if response.content else {"ok": True}
