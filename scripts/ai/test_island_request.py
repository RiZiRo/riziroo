import io
import json
import unittest
import urllib.error

from island_request import build_request, extract_answer, perform


class IslandAiTests(unittest.TestCase):
    def env(self, **changes):
        return {
            "ISLAND_AI_ENDPOINT": "https://example.invalid/v1/chat/completions",
            "ISLAND_AI_QUERY": "Explain a directory.",
            "ISLAND_AI_MODEL": "test-model",
            "ISLAND_AI_REQUEST_ID": "17",
            "ISLAND_AI_KEY": "test-only-secret",
            **changes,
        }

    def test_explicit_nonstream_answer_only_request(self):
        req, fmt = build_request(self.env(ISLAND_AI_PARAMS=json.dumps({
            "stream": True, "temperature": 0.2, "tools": [{}]})))
        body = json.loads(req.data)
        self.assertFalse(body["stream"])
        self.assertNotIn("tools", body)
        self.assertEqual(body["temperature"], 0.2)
        self.assertEqual(body["messages"][-1]["content"], "Explain a directory.")
        self.assertNotIn("test-only-secret", req.full_url)

    def test_gemini_key_header_and_nonstream_endpoint(self):
        req, fmt = build_request(self.env(
            ISLAND_AI_FORMAT="gemini",
            ISLAND_AI_ENDPOINT="https://example.invalid/model:streamGenerateContent"))
        self.assertEqual(fmt, "gemini")
        self.assertTrue(req.full_url.endswith(":generateContent"))
        self.assertNotIn("test-only-secret", req.full_url)
        self.assertEqual(req.get_header("X-goog-api-key"), "test-only-secret")

    def test_gemini_excludes_thoughts(self):
        payload = {"candidates": [{"content": {"parts": [
            {"text": "private reasoning", "thought": True}, {"text": "Visible answer"}]}}]}
        self.assertEqual(extract_answer(payload, "gemini"), "Visible answer")

    def test_success_full_answer_and_generation(self):
        answer = "A long answer. " * 500
        data = json.dumps({"choices": [{"message": {"content": answer}}]}).encode()
        reply = perform(self.env(), lambda *a, **k: io.BytesIO(data))
        self.assertTrue(reply["ok"])
        self.assertEqual(reply["requestId"], "17")
        self.assertEqual(reply["text"], answer.strip())

    def test_content_blocks(self):
        self.assertEqual(extract_answer({"choices": [{"message": {"content": [
            {"type": "text", "text": "Hello"}, {"type": "text", "text": " world"}]}}]}, "openai"), "Hello world")

    def test_errors_do_not_leak_urls_or_keys(self):
        def fail(*args, **kwargs):
            raise urllib.error.HTTPError("https://example.invalid/?key=test-only-secret",
                                         401, "test-only-secret", {}, None)
        reply = perform(self.env(), fail)
        self.assertFalse(reply["ok"])
        self.assertNotIn("test-only-secret", json.dumps(reply))
        self.assertIn("API key", reply["error"])

    def test_empty_malformed_timeout(self):
        for data in (b"{}", b"not json"):
            reply = perform(self.env(), lambda *a, **k: io.BytesIO(data))
            self.assertFalse(reply["ok"])
        def timeout(*args, **kwargs):
            raise TimeoutError()
        self.assertIn("timed out", perform(self.env(), timeout)["error"])


if __name__ == "__main__":
    unittest.main()
