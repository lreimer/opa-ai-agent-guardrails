"""Google ADK agent that researches and answers questions about CLC26 in Mannheim."""

import os

from google.adk.agents import Agent
from google.adk.apps import App
from google.adk.tools import google_search
from google.adk.tools.agent_tool import AgentTool

from .opa_plugin import OpaWasmGuardrailsPlugin
from .tools import fetch_clc_page

MODEL = os.getenv("CLC26_AGENT_MODEL", "gemini-3.8-flash")

# Gemini built-in search cannot be mixed with function tools in one agent, so it is wrapped.
web_search_agent = Agent(
    name="clc26_web_search_agent",
    model=MODEL,
    description="Searches the web via Google Search for information related to the CLC26 conference.",
    instruction=(
        "You search the web with Google Search to answer the given question about the CLC26 "
        "conference (Developer Experience, Platform Engineering and Software Delivery, "
        "11-12 November 2026, Mannheim, Germany) or its speakers, venue and surroundings. "
        "Return a concise factual summary and always list the source URLs you used."
    ),
    tools=[google_search],
)

root_agent = Agent(
    name="clc26_agent",
    model=MODEL,
    description="Researches and answers questions about the CLC26 conference in Mannheim.",
    instruction="""You are a helpful assistant for the CLC26 conference ("CLC – Die Konferenz zu
Developer Experience, Platform Engineering und Software Delivery"), organised by heise / iX and
dpunkt.verlag, taking place on 11 and 12 November 2026 in Mannheim, Germany, with on-site
pre-conference workshops on 10 November 2026.
The official website is https://clc-conference.eu/.

How to research:
1. Prefer official information. Use `fetch_clc_page` to read the conference website, starting with
   "/programm.php" for questions about talks, speakers, tracks, times or rooms, and follow
   "/lecture.php?id=..." links for details of individual talks and workshops.
   Use "/index_en.php", "/konferenz.php", "/tickets_weiche.php" and "/faq.php" for general,
   venue and ticket questions.
2. Use `clc26_web_search_agent` only for information not available on the official website,
   e.g. speaker backgrounds, travel to Mannheim, hotels, or news coverage.
3. Never invent talks, speakers, times or prices. If you cannot find something, say so.

How to answer:
- Answer in the language of the user's question (the website is mostly German).
- Be concise, use lists or tables for schedules, and include times, rooms and speakers when known.
- Always cite the source URLs you used.
""",
    tools=[fetch_clc_page, AgentTool(agent=web_search_agent)],
)

# The plugin applies to all agents of this app, including the wrapped web search agent.
app = App(
    name="clc26_agent",
    root_agent=root_agent,
    plugins=[OpaWasmGuardrailsPlugin()],
)
