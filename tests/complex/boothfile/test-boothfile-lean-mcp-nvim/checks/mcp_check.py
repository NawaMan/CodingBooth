"""Talk to lean-lsp-mcp over stdio, the way Claude Code does, and print what two tools return.

Run with the server's own Python, which has the `mcp` client library:
    /opt/lean-lsp-mcp/bin/python checks/mcp_check.py Exercises/Basic.lean <line>
"""

import asyncio
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


def text(result) -> str:
    return "\n".join(getattr(c, "text", "") for c in result.content)


async def main(file: str, line: int) -> None:
    path = str(Path(file).resolve())
    server = StdioServerParameters(command="lean-lsp-mcp", args=[])
    async with stdio_client(server) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = {t.name for t in (await session.list_tools()).tools}
            print("TOOLS:", " ".join(sorted(tools)))
            goal = await session.call_tool("lean_goal", {"file_path": path, "line": line, "column": 3, "timeout_s": 300})
            print("GOAL:", text(goal))
            diags = await session.call_tool("lean_diagnostic_messages", {"file_path": path, "timeout_s": 300})
            print("DIAGNOSTICS:", text(diags))


asyncio.run(main(sys.argv[1], int(sys.argv[2])))
