#!/usr/bin/env python3
"""One explicit island AI request. Credentials stay in the process environment."""
import json
import os
import socket
import urllib.error
import urllib.request

SYSTEM_PROMPT = (
    "You are a helpful assistant in a Linux desktop launcher. Always answer in English. "
    "Be concise and practical, but provide enough detail to answer the question. "
    "Use readable paragraphs and short lists when useful. You have no tools or access "
    "to the user's files, windows, or desktop state; do not claim to inspect or change them."
)


def build_request(env):
    endpoint = env.get("ISLAND_AI_ENDPOINT", "")
    if not endpoint.startswith(("https://", "http://")):
        raise ValueError("The selected model has no valid endpoint.")
    key = env.get("ISLAND_AI_KEY", "")
    fmt = env.get("ISLAND_AI_FORMAT", "openai")
    prompt = env.get("ISLAND_AI_QUERY", "").strip()
    if not prompt:
        raise ValueError("Type a question first.")
    extra_headers = json.loads(env.get("ISLAND_AI_HEADERS", "{}"))
    extra_params = json.loads(env.get("ISLAND_AI_PARAMS", "{}"))
    if not isinstance(extra_headers, dict) or not isinstance(extra_params, dict):
        raise ValueError("The selected model has invalid request settings.")
    headers = {"Content-Type": "application/json", **extra_headers}
    if fmt == "gemini":
        endpoint = endpoint.replace(":streamGenerateContent", ":generateContent")
        if key:
            headers["x-goog-api-key"] = key
        body = {
            **extra_params,
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        }
    else:
        if key:
            headers["Authorization"] = "Bearer " + key
        body = {
            **extra_params, "model": env.get("ISLAND_AI_MODEL", ""),
            "messages": [{"role": "system", "content": SYSTEM_PROMPT},
                         {"role": "user", "content": prompt}],
            "stream": False,
        }
        for name in ("tools", "tool_choice", "functions", "function_call"):
            body.pop(name, None)
    return urllib.request.Request(endpoint, data=json.dumps(body).encode(), headers=headers, method="POST"), fmt


def extract_answer(payload, fmt):
    if fmt == "gemini":
        candidates = payload.get("candidates") or []
        parts = candidates[0].get("content", {}).get("parts", []) if candidates else []
        answer = "".join(p.get("text", "") for p in parts if not p.get("thought", False))
    else:
        choices = payload.get("choices") or []
        content = choices[0].get("message", {}).get("content", "") if choices else ""
        answer = content if isinstance(content, str) else "".join(
            part.get("text", "") for part in content or [] if isinstance(part, dict))
    if not answer.strip():
        raise ValueError("The provider returned no answer.")
    return answer.strip()


def perform(env, opener=urllib.request.urlopen):
    request_id = env.get("ISLAND_AI_REQUEST_ID", "")
    try:
        request, fmt = build_request(env)
        with opener(request, timeout=45) as response:
            payload = response.read(2 * 1024 * 1024 + 1)
            if len(payload) > 2 * 1024 * 1024:
                raise ValueError("Response too large.")
            answer = extract_answer(json.loads(payload), fmt)
        return {"requestId": request_id, "ok": True, "text": answer, "error": ""}
    except urllib.error.HTTPError as error:
        status = error.code
        error.close()
        message = {
            401: "The provider rejected the API key. Check it in the AI sidebar.",
            403: "The provider denied this request. Check your account or network access.",
            429: "The provider's rate or credit limit was reached. Try again later.",
        }.get(status, f"The provider returned HTTP {status}. Try again later.")
    except (TimeoutError, socket.timeout):
        message = "The request timed out after 45 seconds. You can retry."
    except urllib.error.URLError:
        message = "Could not reach the provider. Check your connection or proxy, then retry."
    except OSError:
        message = "The connection ended before the answer arrived. You can retry."
    except json.JSONDecodeError:
        message = "The provider returned an unreadable response."
    except (ValueError, TypeError, KeyError, AttributeError):
        message = "No usable answer was returned. Check the model in the sidebar or retry."
    # Never expose raw exceptions/URLs: endpoints may contain credentials.
    return {"requestId": request_id, "ok": False, "text": "", "error": message}


if __name__ == "__main__":
    print(json.dumps(perform(os.environ), ensure_ascii=True), flush=True)
