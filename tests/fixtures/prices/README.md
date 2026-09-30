# Price-source fixtures

Synthetic payloads for `tests/trace-prices.test.sh`, in the shapes the two
machine-readable price sources really publish:

| File | Shape it imitates |
| --- | --- |
| `litellm-moved.json` | LiteLLM's `model_prices_and_context_window.json` — one object per model key, costs **per token** |
| `litellm-partial.json` | the same, missing one of the five models the refresh script maps |
| `openrouter-moved.json` | OpenRouter's `/api/v1/models` — a `data` array, `pricing` strings **per token** |
| `openrouter-disagrees.json` | the same, with one model's input price doubled, so the two sources disagree past the threshold |

**Every number here is deliberately absurd** — 7.77, 33.33, 9.71 and friends,
repeating digits no vendor has ever charged. That is the point: the suite
proves a refresh moved the price table's five entries to *these* values, and a
fixture that could plausibly equal a real price would make that assertion pass
by coincidence on the day the real prices happened to match.

The model ids are this repo's own (the five that `scripts/agents.kit.config.sh`
maps). The `codex:` prefix a dispatched model carries in an event is the
dispatcher's, not the vendor's, so it appears in neither source and neither
file carries it — `scripts/trace-prices.kit.sh` holds the mapping table that
strips it for the lookup.

Kit-authoring only: `bootstrap.sh`'s `KIT_ONLY` list deletes this directory's
files, the same as `tests/` around it.
