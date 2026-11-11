import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, call, patch

import httpx

from agents.qaware_agent.opa_rest_plugin import (
    ALLOW_QUERY,
    DENY_REASONS_QUERY,
    OpaRestGuardrailsPlugin,
)


def _opa_response(result):
    return httpx.Response(
        200,
        json={"result": result},
        request=httpx.Request("POST", "http://opa.test"),
    )


class OpaRestGuardrailsPluginTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.client = AsyncMock()
        self.client.aclose = AsyncMock()
        client_patcher = patch(
            "agents.qaware_agent.opa_rest_plugin.httpx.AsyncClient",
            return_value=self.client,
        )
        client_patcher.start()
        self.addCleanup(client_patcher.stop)
        self.plugin = OpaRestGuardrailsPlugin(opa_url="http://opa.test", timeout=0.5)

    async def asyncTearDown(self):
        await self.plugin.close()

    async def test_allowed_decision_posts_input_to_allow_endpoint(self):
        decision_input = {"phase": "before_tool", "tool": "fetch_qaware_page"}
        self.client.post.return_value = _opa_response(True)

        allowed = await self.plugin._allowed(decision_input)

        self.assertTrue(allowed)
        self.client.post.assert_awaited_once_with(
            f"http://opa.test{ALLOW_QUERY}",
            json={"input": decision_input},
        )

    async def test_denial_includes_reasons_from_reasons_endpoint(self):
        tool = SimpleNamespace(name="fetch_qaware_page")
        tool_context = SimpleNamespace(agent_name="qaware_agent")
        tool_args = {"path_or_url": "https://evil.example"}
        decision_input = {
            "phase": "before_tool",
            "agent": "qaware_agent",
            "tool": "fetch_qaware_page",
            "arguments": tool_args,
        }
        self.client.post.side_effect = [
            _opa_response(False),
            _opa_response(["Host is not allowed."]),
        ]

        blocked_result = await self.plugin.before_tool_callback(
            tool=tool,
            tool_args=tool_args,
            tool_context=tool_context,
        )

        if blocked_result is None:
            self.fail("denied tool call should return an error result")
        self.assertEqual(blocked_result["status"], "error")
        self.assertIn("🚫 Host is not allowed.", blocked_result["error_message"])
        self.client.post.assert_has_awaits(
            [
                call(
                    f"http://opa.test{ALLOW_QUERY}",
                    json={"input": decision_input},
                ),
                call(
                    f"http://opa.test{DENY_REASONS_QUERY}",
                    json={"input": decision_input},
                ),
            ]
        )

    async def test_opa_connection_error_fails_closed(self):
        request = httpx.Request("POST", f"http://opa.test{ALLOW_QUERY}")
        self.client.post.side_effect = httpx.ConnectError("OPA unavailable", request=request)

        with self.assertLogs("agents.qaware_agent.opa_rest_plugin", level="ERROR"):
            allowed = await self.plugin._allowed({"phase": "before_model"})

        self.assertFalse(allowed)

    async def test_missing_result_fails_closed(self):
        self.client.post.return_value = httpx.Response(
            200,
            json={},
            request=httpx.Request("POST", f"http://opa.test{ALLOW_QUERY}"),
        )

        with self.assertLogs("agents.qaware_agent.opa_rest_plugin", level="ERROR"):
            allowed = await self.plugin._allowed({"phase": "before_model"})

        self.assertFalse(allowed)

    async def test_non_boolean_allow_result_fails_closed(self):
        self.client.post.return_value = _opa_response(1)

        allowed = await self.plugin._allowed({"phase": "before_model"})

        self.assertFalse(allowed)


if __name__ == "__main__":
    unittest.main()
