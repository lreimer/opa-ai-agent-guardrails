# Open Policy Agent AI Guardrails

Demo repository for AI agent guardrails using OPA.

## CLC26 Conference Agent (Google ADK)

The [agents/clc26_agent](agents/clc26_agent) directory contains a Python [Google ADK](https://adk.dev/) agent
that researches and answers questions about the [CLC26 conference](https://clc-conference.eu/)
(11-12 November 2026, Mannheim). It reads the official conference website (programme, talks, tickets, FAQ)
and falls back to Google Search for everything else.

```bash
cp agents/clc26_agent/.env.example agents/clc26_agent/.env   # add your Gemini API key or Vertex AI project
make adk-web                                                 # open http://localhost:8000 and select clc26_agent
```

Use `ADK_WEB_PORT=9000 make adk-web` to change the port and `CLC26_AGENT_MODEL` to override the Gemini model.

## Maintainer

M.-Leander Reimer (@lreimer), <mario-leander.reimer@qaware.de>

## License

This software is provided under the MIT open source license, read the `LICENSE` file for details.
