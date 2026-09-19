# Multi-provider AI and dynamic model discovery with pricing metadata

Support user-configurable cloud LLM providers (Google Gemini, Anthropic Claude, and Hugging Face Inference) alongside on-device models, with dynamic model listing and pricing metadata fetched directly from provider APIs.

- Status: accepted
- Date: 2026-09-19

## Context

Prior to this decision, BNPB only supported local Gemma 3n via `flutter_gemma` and a single hardcoded cloud model (`gemini-2.5-flash`). Users requested the ability to use Claude (Anthropic), other Gemini models, and Hugging Face models, complete with dynamic model discovery and cost/pricing visibility so that new models do not require manual app updates or code changes.

## Decision

1. **Provider Abstraction**: Expand `LocalLlmService` backends to support:
   - `local`: On-device LiteRT / MediaPipe models (Gemma, Phi, etc.)
   - `gemini`: Google Generative AI API with user key
   - `claude`: Anthropic Messages API with user key
   - `huggingface`: Hugging Face Serverless Inference / Dedicated Endpoints with user token
2. **Dynamic Model Discovery**:
   - Query provider model listing endpoints dynamically (e.g. `https://generativelanguage.googleapis.com/v1beta/models`, `https://api.anthropic.com/v1/models`, and Hugging Face hub API `https://huggingface.co/api/models`).
   - Cache discovered models locally with TTL to minimize network requests.
3. **Pricing Metadata**:
   - Accompany discovered models with per-million token pricing (input / output) using a built-in provider rate-card family heuristic with an optional remote pricing manifest fallback.
4. **Hugging Face Scope**:
   - Filter Hugging Face Hub queries to trending `text-generation` models (e.g. Llama, Mistral, Qwen, DeepSeek, Gemma) with an autocomplete input permitting any custom repository ID.
5. **Per-Provider Model Persistence**:
   - Store selected models per provider independently (`ai.provider.<provider>.model`), defaulting to the provider's fastest/budget flagship (`gemini-2.5-flash`, `claude-3-5-haiku-latest`).
6. **Security & Privacy**:
   - All provider API keys are stored exclusively in the device secure storage (`SecurityService`).
   - Cloud AI remains strictly opt-in; default remains on-device.


## Consequences

Adding new models requires zero app updates; newly launched models from Google or Anthropic appear in the user's dropdown as soon as they are listed on the provider's API. Users have transparent per-token pricing visibility directly in the settings dropdown before choosing a model.
