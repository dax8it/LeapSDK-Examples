---
name: ai-sdk
description: Answer questions about the AI SDK and help build AI-powered features. Use when developers: (1) Ask about AI SDK functions like generateText, streamText, ToolLoopAgent, or tools, (2) Want to build AI agents, chatbots, or text generation features, (3) Have questions about AI providers (OpenAI, Anthropic, etc.), streaming, tool calling, or structured output.
---
# AI SDK

## Overview
Use for streaming text+audio patterns, tool calling, and prompt handling.

## Agent Behavior Contract
1. Ensure system prompt is exact and appears once.
2. Use streaming callbacks safely; avoid UI updates off-main.
3. Prefer incremental, cancellable generation flows.
4. Keep prompts grounded in local context only.

## Project Notes
- Requires interleaved text+audio responses.
