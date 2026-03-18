/**
 * Builds the Anthropic API payload with or without prompt caching.
 * Prompt caching requires the beta header: anthropic-beta: prompt-caching-2024-07-31
 * Cache blocks must be >= 1024 tokens. Content with cache_control is written to
 * the KV cache on first use (25% surcharge) and read back cheaply (10% of normal price).
 */
export function buildAnthropicRequest(question, useCache, fewShot, systemPrompt) {
  const model = 'claude-haiku-4-5';

  // ── System prompt: cache the full static block ──────────
  const system = useCache
    ? [{ type: 'text', text: systemPrompt, cache_control: { type: 'ephemeral' } }]
    : [{ type: 'text', text: systemPrompt }];

  // ── Messages: cache few-shot examples then append user question ──
  const messages = [];
  if (useCache) {
    // Interleave few-shot; mark the LAST assistant turn for caching
    for (let i = 0; i < fewShot.length; i++) {
      const turn = fewShot[i];
      const isLastAssistant = turn.role === 'assistant' && i === fewShot.length - 1;
      messages.push({
        role: turn.role,
        content: isLastAssistant
          ? [{ type: 'text', text: turn.content, cache_control: { type: 'ephemeral' } }]
          : turn.content
      });
    }
  } else {
    fewShot.forEach(t => messages.push(t));
  }

  messages.push({ role: 'user', content: question });

  return {
    model,
    payload: {
      model,
      max_tokens: 512,
      system,
      messages
    }
  };
}

/**
 * Extract token usage from Anthropic response.
 * cache_creation_input_tokens = tokens written to cache (billed at 1.25×)
 * cache_read_input_tokens     = tokens loaded from cache (billed at 0.10×)
 * input_tokens                = uncached input tokens (billed at 1×)
 * output_tokens               = generated tokens (billed at standard output rate)
 */
export function parseUsage(raw = {}) {
  return {
    cacheWriteTokens: raw.cache_creation_input_tokens || 0,
    cacheReadTokens:  raw.cache_read_input_tokens     || 0,
    inputTokens:      raw.input_tokens                || 0,
    outputTokens:     raw.output_tokens               || 0
  };
}

/**
 * Approximate cost for Claude Haiku (prices per million tokens, USD):
 *   Input:        $0.80  / MTok
 *   Cache write:  $1.00  / MTok  (1.25× of input)
 *   Cache read:   $0.08  / MTok  (0.10× of input)
 *   Output:       $4.00  / MTok
 * Source: Anthropic pricing page, verified Jan 2025.
 * NOTE: Verify current rates at https://www.anthropic.com/pricing before production use.
 */
const PRICES = {
  input:       0.80  / 1_000_000,
  cacheWrite:  1.00  / 1_000_000,
  cacheRead:   0.08  / 1_000_000,
  output:      4.00  / 1_000_000
};

export function computeCost(usage, useCache) {
  const inputCost  = usage.inputTokens    * PRICES.input;
  const writeCost  = usage.cacheWriteTokens * PRICES.cacheWrite;
  const readCost   = usage.cacheReadTokens  * PRICES.cacheRead;
  const outputCost = usage.outputTokens   * PRICES.output;
  const total = inputCost + (useCache ? writeCost + readCost : 0) + outputCost;
  return {
    inputCost:  inputCost.toFixed(8),
    writeCost:  writeCost.toFixed(8),
    readCost:   readCost.toFixed(8),
    outputCost: outputCost.toFixed(8),
    total
  };
}
