// Populates the "lemonade" provider's model list from the running lemonade
// server, so config.json never hardcodes model names. If lemonade is down,
// the provider is left as-is (empty models -> hidden).
//
// All downloaded chat-capable models are listed. If config.json defines an
// entry for a model id (custom label, tool_call, etc.), that entry wins;
// models lemonade has that config.json doesn't mention get a generated label
// with a recipe/device hint (FLM = NPU, llamacpp = iGPU).
const BASE = "http://127.0.0.1:9002"

const NON_CHAT_LABELS = new Set([
  "image",
  "edit",
  "upscaling",
  "embedding",
  "reranking",
  "transcription",
  "tts",
])

const RECIPE_HINTS = { flm: "NPU", llamacpp: "iGPU" }

async function getJSON(path) {
  const res = await fetch(`${BASE}${path}`, { signal: AbortSignal.timeout(2000) })
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`)
  return res.json()
}

export const LemonadeModels = async () => {
  return {
    config: async (config) => {
      let catalog, health
      try {
        catalog = await getJSON("/api/v1/models")
      } catch {
        return // lemonade not running; leave config untouched
      }
      try {
        health = await getJSON("/api/v1/health")
      } catch {
        health = {}
      }

      // Context size lemonade actually allocated for the loaded model; other
      // models fall back to lemonade's usual load default.
      const loaded = (health.all_models_loaded ?? []).find((m) => m.loaded)
      const loadedCtx = loaded?.recipe_options?.ctx_size ?? 32768

      const chatModels = (catalog.data ?? [])
        .filter((m) => m.downloaded)
        .filter((m) => !(m.labels ?? []).some((l) => NON_CHAT_LABELS.has(l)))
      if (!chatModels.length) return

      config.provider ??= {}
      const lemonade = (config.provider.lemonade ??= {})
      lemonade.npm ??= "@ai-sdk/openai-compatible"
      lemonade.name ??= "Lemonade"
      lemonade.options ??= { baseURL: `${BASE}/api/v1`, apiKey: "lemonade" }

      const fromConfig = lemonade.models ?? {}
      lemonade.models = {}
      for (const m of chatModels) {
        const hint = RECIPE_HINTS[m.recipe] ?? m.recipe
        const ctx = m.id === loaded?.model_name ? loadedCtx : 32768
        lemonade.models[m.id] = fromConfig[m.id] ?? {
          name: `${m.id} (${hint})`,
          tool_call: (m.labels ?? []).includes("tool-calling"),
          reasoning: (m.labels ?? []).includes("reasoning"),
          limit: { context: ctx, output: 8192 },
        }
      }

      // "lemonade" (no model id) in config.json means: use the loaded model.
      if (!config.model || config.model === "lemonade") {
        const ids = chatModels.map((m) => m.id)
        const current =
          health.model_loaded && ids.includes(health.model_loaded)
            ? health.model_loaded
            : ids[0]
        config.model = `lemonade/${current}`
      }
    },
  }
}
