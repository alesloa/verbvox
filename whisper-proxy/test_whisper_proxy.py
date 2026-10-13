"""Gate behaviour for whisper_proxy: wrong/missing token -> 401, correct token
forwards to upstream and never leaks the token onward."""
import os
import unittest
from unittest import mock

os.environ["WHISPER_PROXY_TOKEN"] = "test-secret-123"
os.environ["WHISPER_PROXY_PARAM"] = "somos"

import whisper_proxy  # noqa: E402  (env must be set before import)


class GateTests(unittest.TestCase):
    def setUp(self):
        self.client = whisper_proxy.create_app().test_client()

    def test_missing_token_is_401(self):
        self.assertEqual(self.client.get("/inference").status_code, 401)

    def test_wrong_token_is_401(self):
        self.assertEqual(self.client.get("/inference?somos=nope").status_code, 401)

    @mock.patch("whisper_proxy.requests.request")
    def test_valid_token_forwards(self, mreq):
        mreq.return_value = mock.Mock(
            status_code=200, content=b'{"text":"hi"}',
            headers={"Content-Type": "application/json"},
        )
        r = self.client.post("/inference?somos=test-secret-123",
                             data=b"audio", content_type="audio/wav")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data, b'{"text":"hi"}')
        _, kwargs = mreq.call_args
        self.assertNotIn("somos", kwargs["params"])          # token not forwarded
        self.assertTrue(kwargs["url"].endswith("/inference"))

    @mock.patch("whisper_proxy.requests.request")
    def test_empty_secret_denies_and_never_forwards(self, mreq):
        with mock.patch.dict(os.environ, {"WHISPER_PROXY_TOKEN": ""}):
            r = self.client.get("/inference?somos=")
        self.assertEqual(r.status_code, 401)
        mreq.assert_not_called()


if __name__ == "__main__":
    unittest.main()
