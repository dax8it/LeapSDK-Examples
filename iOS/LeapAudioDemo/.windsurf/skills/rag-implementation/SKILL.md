---
name: rag-implementation
description: Build Retrieval-Augmented Generation (RAG) systems for LLM applications with vector databases and semantic search. Use when implementing knowledge-grounded AI, building document Q&A systems, or integrating LLMs with external knowledge bases.
---
# RAG Implementation

## Overview
Use for local retrieval/context packing from JSON and lightweight caching.

## Agent Behavior Contract
1. Keep retrieval local and on-device; no network calls.
2. Prefer simple, deterministic retrieval over heavy indexing.
3. Keep context packets compact and grounded in exhibit JSON.
4. Fail gracefully on missing/corrupt JSON with user-visible fallback.

## Project Notes
- Exhibit data lives in `Exhibits/Data` with per-exhibit folders.
- Context builders should only use provided metadata.
