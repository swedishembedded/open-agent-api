# Open Agent API – OpenAPI Schema

The **Open Agent API** is a web protocol for connecting intelligent agents and providing secure, multi-tenant access to their capabilities. It supports clients generated in languages that OpenAPI generators support.

The schema developed in `open-agent-api.yaml` is designed to be **extensible** and covers authentication, agent interaction (including streaming events), team-based agents, knowledge search, and optional billing (Stripe) integration. 

## Authentication

The API supports two authentication flows: a **magic link** email flow and an **OAuth2** flow (compatible with Clerk or any OAuth provider). These enable passwordless login or third-party login, resulting in a bearer token or API key for use in subsequent requests.

- **Magic Link (Email)**: Clients can request a magic login link to be emailed to a user. For example, services like Stytch and MojoAuth use endpoints to send magic links via email. In our API, an unauthenticated client calls `POST/auth/link` with an email address; the server emails a one-time link. The link contains a token which is then submitted to `GET /auth/link/verify` for validation. On success, the API issues a session JWT or API key for authenticated use. (The verify could return a JWT in JSON or set a cookie for web clients.)

- **OAuth2 (Clerk-compatible)**: The API integrates with OAuth providers (Google, GitHub, etc.) in a provider-agnostic way. The client directs the user to the provider's auth page, then the provider redirects to our `GET /auth/oauth/{provider}/callback` endpoint with an auth code. The server exchanges the code for an access token and obtains user info, then creates/identifies the user and issues a JWT/API token. This design is compatible with the approach of supporting many social login providers The OpenAPI security scheme is defined for Bearer auth (JWT or API key) in the `Authorization` header. 

**Security**: Most endpoints require authentication. We allow either a user JWT (from magic link/OAuth) or an API key. API keys (issued per user or team) are used for programmatic access to agent and chat endpoints, similar to OpenAI's API keys. (OpenAI also uses a bearer token in the Authorization header for API keys. The OpenAPI spec defines `BearerAuth` as the security scheme for simplicity (the token can represent either a user session or an API key). 

## Stripe Integration (Optional)

For monetization, the API optionally integrates with **Stripe** to manage subscription tiers and usage limits. Multiple subscription plans can be defined (e.g. Free, Pro, Enterprise), each with limits on API usage, number of agents, etc. Stripe webhooks are used to keep the system in sync with billing events.  For example, Stripe sends an `invoice.paid` event when an invoice is successfully paid (signaling a subscription renewal or upgrade) ([Using webhooks with subscriptions | Stripe Documentation](https://docs.stripe.com/billing/subscriptions/webhooks#:~:text=,when%20the%20invoice%20requires%20action)), and sends events when subscriptions are created or canceled. Our webhook endpoint (`POST /stripe/webhook`) listens for events like `invoice.paid`, `invoice.payment_failed`, `customer.subscription.created`, `customer.subscription.updated`, and `customer.subscription.deleted`. On receiving these, the server updates the user's plan status, usage counters, or agent limits accordingly. 

This design handles **subscription lifecycle events** such as creation, updates, cancellations, and upgrades ([Stripe | Better Auth](https://www.better-auth.com/docs/plugins/stripe#:~:text=,subscriptions%20with%20users%20or%20organizations)).  For instance, when a new subscription is created or an upgrade occurs, the user's account is updated to the new tier. Usage tracking (API calls, agent interactions) is recorded to enforce plan limits (e.g. number of messages per month). The API may expose an endpoint like `GET /account/usage` or include usage data in responses to help users monitor their consumption. (In the OpenAPI schema, the Stripe integration paths are marked optional and can be omitted if not needed.) All Stripe webhook payloads are verified via signature for security ([Stripe | Better Auth](https://www.better-auth.com/docs/plugins/stripe#:~:text=,subscriptions%20with%20users%20or%20organizations)).

## Chat Completion API

The Open Agent API provides a **Chat Completion** endpoint compatible with OpenAI's API. This allows direct low-level access to underlying language models (provider models or fine-tuned models) using the same format as OpenAI's `/v1/chat/completions`. The goal is to let customers reuse existing OpenAI client code by simply pointing it to this API.

This includes supporting endpoints like:

```text
GET  /v1/models
POST /v1/chat/completions
POST /v1/embeddings
POST /v1/completions
```

- **Endpoint**: `POST /v1/chat/completions`  
- **Request**: JSON with a `model` (e.g. `"gpt-4"` or provider-specific model ID) and a list of `messages`. Each message has a `role` (`user`, `assistant`, or `system`) and `content`. This mirrors OpenAI's format ([OpenAI | API References - Zenlayer Docs](https://docs.console.zenlayer.com/api-reference/aigw/dialogue-generation/openai-chat-completion#:~:text=OpenAI%20%7C%20API%20References%20,4%22%2C%20%22messages%22%3A%20%5B)). Optional parameters like `temperature`, `top_p`, `n`, `stop`, `max_tokens`, etc., are supported to control generation, matching OpenAI's API. For compatibility, the request may also accept `stream: true` to get a streamed response (though our design primarily uses the `Accept: text/event-stream` header for streaming, see below).

- **Response**: By default (non-streaming), a JSON object with an `id`, `object` = `"chat.completion"`, `created` timestamp, and `model` echo. The main content is in `choices` – an array of one or more completions. Each choice contains a `message` (with `role: "assistant"` and the generated `content`) and a `finish_reason`. We also include a `usage` object with token counts (`prompt_tokens`, `completion_tokens`, `total_tokens`) to facilitate user billing or monitoring (similar to OpenAI's usage field). The schema follows OpenAI's response spec ([OpenAI Compatibility API | LM Studio Docs](https://lmstudio.ai/docs/api/openai-api#:~:text=,0.7)). 

- **Streaming**: If the client sets `Accept: text/event-stream`, the server will stream the completion in segments. This works like OpenAI's streaming, sending partial messages as events. Each SSE data payload contains a JSON with a `delta` (partial content) until an end-of-stream signal (or a final event). In our spec, the Chat Completion endpoint supports both `application/json` (for full response) and `text/event-stream` (for streaming). (See **Agents API** below for event schema.)

- **Authentication**: The Chat endpoint requires an API key or valid token (as per the security scheme). This ensures only authorized customers (with proper plan limits) can use the models. The design is provider-agnostic: behind this API, requests may be fulfilled by OpenAI, Anthropic, local models, etc., but that is abstracted away from the client.

## Agents API

Agents are stateful, reasoning entities built on top of the base models. The Agents API allows customers to create, configure, and interact with individual agents that have specific skills, tools, or personas. An agent could represent a particular workflow or autonomous task logic. (Agno, for instance, treats each agent as an AI worker with specific instructions and tools ([Agentic Framework Deep Dive Series (Part 2): Agno | by Devi | Apr, 2025 | Medium](https://medium.com/@devipriyakaruppiah/agentic-framework-deep-dive-series-part-2-agno-c45da579b7c0#:~:text=,and%20pull%20in%20necessary%20data)).)

**Create an Agent**: `POST /agents` – Register a new agent. The client provides a name, base `model` (choosing from the provider's offerings), and optional configuration such as a default `prompt` or `description` of the agent's role. The request can also include a list of allowed `tools` for the agent (each tool with a name and description of its functionality). Tools act like plugins giving the agent extra abilities ([Agentic Framework Deep Dive Series (Part 2): Agno | by Devi | Apr, 2025 | Medium](https://medium.com/@devipriyakaruppiah/agentic-framework-deep-dive-series-part-2-agno-c45da579b7c0#:~:text=,and%20pull%20in%20necessary%20data)). The response returns an `agent_id` and the agent's details. (Agents are associated with the authenticated user's account.)

**List/Get Agents**: `GET /agents` returns the user's agents with basic info (id, name, model). `GET /agents/{agentId}` returns detailed config of a specific agent (including its tool list and any settings).

**Chat with an Agent**: `POST /agents/{agentId}/chat` – This endpoint is used to have a conversation or run a task with a particular agent. The request body includes a `messages` array, similar to the Chat Completion API (roles can be `user`, `assistant`, and possibly `system` for context). The difference is that the agent's own persona and tools come into play. You can also optionally pass in a `tools` array here describing available tools for this conversation (if not already defined globally for the agent), allowing dynamic tool availability per request. 

- If the client **does not** request streaming (no SSE), this call will block until the agent produces a final answer. The response (200) will contain the agent's reply in a structure similar to a single-turn chat completion (e.g. `{ "message": {...}, "finish_reason": ..., "usage": {...} }`). Essentially, the agent will internally handle any reasoning or tool usage and just return the end result.

- If the client wants **streaming** interaction, it sets `Accept: text/event-stream`. In this mode, the server will **stream server-sent events (SSE)** as the agent thinks and acts. The event stream allows the client to receive intermediate outputs (e.g. thoughts, partial answers, or tool requests) in real time. This design is inspired by Google's A2A protocol, which uses SSE for short-running interactive tasks ([A2A and MCP: Start of the AI Agent Protocol Wars? - Koyeb](https://www.koyeb.com/blog/a2a-and-mcp-start-of-the-ai-agent-protocol-wars#:~:text=,the%20client%20once%20its%20finished)). 

  We define a series of event types to structure the streamed conversation:
  - **RunStarted** – emitted at the start of agent processing (e.g. to signify the agent received the prompt and began working).
  - **RunResponse** – emitted one or more times as the agent generates output. These events may include partial chat messages or other data. Notably, if the agent decides to use a **tool**, it will emit a RunResponse (or a specific **ToolRequest** event) indicating which tool it wants to invoke and with what input. At this point, the agent **halts** awaiting the tool result. This is analogous to A2A's `input-required` state where the agent pauses for external input ([A2A/README.md at main · google/A2A · GitHub](https://github.com/google/A2A/blob/main/README.md#:~:text=3.%20Processing%3A%20,completed)). The client (or server automation) should catch the tool request event, execute the requested tool action, and then call the agent again (e.g. by appending the tool's result to the messages and resuming the conversation). Tools effectively let the agent fetch data or perform actions beyond the model's knowledge ([Agentic Framework Deep Dive Series (Part 2): Agno | by Devi | Apr, 2025 | Medium](https://medium.com/@devipriyakaruppiah/agentic-framework-deep-dive-series-part-2-agno-c45da579b7c0#:~:text=,and%20pull%20in%20necessary%20data)).
  - **RunCompleted** – emitted when the agent has finished the conversation turn. This final event contains the agent's completed answer (and possibly a summary or any artifacts). After this, the SSE stream is closed. The final message is also included here for convenience, along with usage statistics or any additional info.

In the SSE JSON data, we include fields like `type` (event type name, e.g.
"RunStarted", "ToolRequest", etc.), and `content` which may be a partial message
or tool instruction.

For a ToolRequest event, for example, the data might look like:

```json
{
    "type": "ToolRequest",
    "tool": "<ToolName>",
    "input": "<ToolInput>"
}
```

The client then fulfills the tool action and sends another
`POST /agents/{agentId}/chat` with the new messages (including the tool result). This
loop continues until RunCompleted. This interactive tool usage pattern allows
agents to be autonomous and extend their capabilities by leveraging external
functions (similar to function calling in LLMs). It aligns with emerging
standards where separating tools from agents lets them access external data
safely

All agent chat events and responses are **JSON-formatted** for ease of parsing. The SSE stream simply prefixes them with the `data:` notation per SSE spec. If a client is not using SSE, they must handle tools manually by pre-processing (or they receive only final output, meaning the agent could not use any out-of-band tools unless the server itself integrates them internally).

## Teams API

The Teams API allows grouping multiple agents into a coordinated team. A team has a designated *team leader* agent that orchestrates the others. This is useful for complex tasks that require multiple specialized agents working together ([Agentic Framework Deep Dive Series (Part 2): Agno | by Devi | Apr, 2025 | Medium](https://medium.com/@devipriyakaruppiah/agentic-framework-deep-dive-series-part-2-agno-c45da579b7c0#:~:text=4.%20Multi)). For example, one agent could handle web searching, another code analysis, and a third creative writing, all supervised by the leader agent that divides the problem.

**Create Team**: `POST /teams` – Creates a new team. The client provides a team name and a list of member agents (by ID) with assigned roles. Each role is just a descriptor (e.g. "Researcher", "Coder", "Presenter") describing that agent's responsibility. The first agent in the list (or an explicitly flagged one) can be the leader, or the system can designate one. The team leader agent is effectively an agent itself (could be one of the provided agents or a new orchestrator agent created implicitly). The response returns a `team_id` and the team composition.

**Team Structure**: Internally, the team leader will maintain the list of agents and their roles. A client can retrieve this via `GET /teams/{teamId}` which returns the team info including member agent IDs, their roles, and which one is leader. This fulfills the requirement that the team leader can "list agents and their roles" to the client.

**Chat with a Team**: `POST /teams/{teamId}/chat` – Works similarly to the single Agent chat, except now the team (via its leader) collectively responds to the query. The client sends a message or conversation to the team. The team leader agent receives the user message and decides how to utilize team members. It may break the problem into sub-tasks and route them to specific agents, then integrate their answers. The streaming behavior and events are analogous to the single agent case: if `Accept: text/event-stream` is used, the client will see events like RunStarted, RunResponse, ToolRequest (from any agent), etc., coming from the team leader as it orchestrates. The leader agent might also emit an event when delegating to a member or when a member returns an answer, but those can be represented as intermediate RunResponse events (with perhaps a field identifying which sub-agent said what). 

The team leader uses each member agent's defined tools and skills. If a member agent requires a tool during its part, the process halts with a ToolRequest event just as in single-agent mode. The client executes it and then continues the chat (still with the team endpoint, including the tool result associated with the appropriate agent's context). This design effectively nests the agent tool-handling loop inside the team orchestration loop.

**Roles and Delegation**: Because each agent in the team has a role, the leader can decide which agent(s) to consult for a given user query. The OpenAPI schema might allow the client to hint which agents to use via the input (or this can be entirely autonomous). We ensure that the team chat endpoint returns a final unified answer (RunCompleted) that  aggregates contributions from members. For traceability, the streamed events could include metadata of which agent is "speaking" at any time. (For example, a RunResponse event could have `{ "from": "<AgentName>", "content": "..." }` if the leader is relaying an answer from a member.)

The Teams API is designed to be extensible. In the future, we might add
endpoints to add or remove members (`POST /teams/{teamId}/agents`) or to change
roles, etc. For this version, creating and querying teams is sufficient. This
multi-agent orchestration approach follows patterns in frameworks like Agno
which allow specialized agents to collaborate on complex tasks

([Agentic Framework Deep Dive Series (Part 2): Agno | by Devi | Apr, 2025 | Medium](https://medium.com/@devipriyakaruppiah/agentic-framework-deep-dive-series-part-2-agno-c45da579b7c0#:~:text=4.%20Multi)).

## Knowledge Search API

To augment agents with domain-specific knowledge, the API provides a **Knowledge
Search** endpoint. This is a secured (API-key protected) service that performs
semantic search over a repository of documents or embeddings that the user makes
accessible to his agents. It enables Retrieval-Augmented Generation (RAG)
workflows by fetching relevant information for a query. The endpoints provide
low level access to this knowledge database and both allows other agents to
reuse the same knowledge and to modify the knowledge that is available to
existing agents.

- **Endpoint**: `POST /knowledge/search`  
- **Request**: JSON containing a `query` (the user's query or keywords to search). Optionally, it could include filters or a specified knowledge corpus ID if multiple collections exist, but for MVP we assume a default knowledge base per user or global.

- **Operation**: The server uses embedding-based search to find documents or snippets that are semantically similar to the query. (Each document in the knowledge base has a vector embedding computed; the query is embedded and compared against these to find top hits.) This is done server-side, so the client doesn't need to supply embeddings, only the text query.

- **Response**: A JSON object with an array of `results`. Each result could include fields like `id` (document identifier), `text` (a relevant excerpt or summary), maybe a `score` (similarity score), and any metadata (e.g. source or title). Only read-access (search) is provided in this MVP. For example:
  ```json
  {
    "results": [
      { "id": "doc123", "text": "Excerpt about topic X ...", "score": 0.87 },
      { "id": "doc456", "text": "Excerpt about topic Y ...", "score": 0.85 }
    ]
  }
  ```
  The results can be used by the client (or an agent) to incorporate into answers. 

This API does not yet include full CRUD for the knowledge base (adding, updating, deleting documents), but it's designed with extensibility in mind. We anticipate adding endpoints like `POST /knowledge` (to add a document) or `DELETE /knowledge/{docId}` in future iterations. The current design can accommodate that without breaking changes (e.g., the `id` in results corresponds to how a future `DELETE` would reference the document).

Security for knowledge search is important since the data may be user-specific. Each request must include the API key or auth token, and the search will be scoped to that user's allowed knowledge sources.

## OpenAPI Schema

The OpenAPI schema for Open Agent API is defined in `open-agent-api.yaml`.

## Documentation

The Open Agent API comes with automatically generated interactive documentation using industry-standard tools:

- **ReDoc** - Clean, responsive documentation
- **Swagger UI** - Interactive API explorer with request/response testing

To generate and access the documentation:

```bash
# Install dependencies
npm install

# Generate documentation
npm run docs

# Start documentation server
npm run serve-docs
```

Then visit:
- http://localhost:8080/redoc/index.html - for ReDoc documentation
- http://localhost:8080/swagger-ui/index.html - for Swagger UI

You can easily link to specific API sections in your documentation by using URL fragments. For more details, see [Documentation README](./docs/README.md).

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Copyright

Copyright © 2025 Martin Schröder, Swedish Embedded AB

This project is developed and maintained by Martin Schröder at Swedish Embedded AB.