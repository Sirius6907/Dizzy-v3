// support-answer — tier 2 of the support brain (v1.3.3-T4).
//
// Flow: the app answers from its bundled FAQ first. Only when that score
// is weak does it call this function. Here we rank the server KB and, if a
// cheap LLM key exists (GROQ_API_KEY / GEMINI_API_KEY / OPENROUTER_API_KEY),
// ask it to phrase the answer in the user's language. With no key we
// return the best KB row verbatim — the feature works before any key.
//
// Body: { question, lang, device_code?, trail?, codes?[] }
// Returns: { tier, answer, matched_id, score, suggest_ticket }
//
// Why Edge + cheap LLM rather than a self-hosted 120B: a 120B needs ~80GB
// VRAM (impossible on free tier, heavy monthly GPU bill), while per-ticket
// cost at Edge is negligible and answer quality comes from KB coverage,
// not raw model size.
//
// PRIVACY: the question is the user's own words. It is forwarded to the
// configured LLM provider ONLY, never logged here, and the KB log row
// stores it as admin-only (support_answers).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const QUESTION_MAX = 500;
const CODE_MAX = 64;
const TRAIL_MAX = 240;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

/** Enum-only token, same rule as the error pipeline. */
function strictToken(raw: unknown, max: number): string {
  const v = String(raw ?? "").trim().toLowerCase();
  if (v.length === 0 || v.length > max) return "";
  return /^[a-z][a-z0-9_]{0,31}$/.test(v) ? v : "";
}

function strictTrail(raw: unknown): string {
  const v = String(raw ?? "").trim().toLowerCase();
  if (v.length === 0 || v.length > TRAIL_MAX) return "";
  for (const t of v.split(">")) {
    if (!/^[a-z][a-z0-9_]{0,31}$/.test(t)) return "";
  }
  return v;
}

function strictLang(raw: unknown): string {
  const v = String(raw ?? "").trim().toLowerCase();
  return v === "hi" ? "hi" : "en";
}

/** Trim + cap the user's own words. Never used in a query, only logged. */
function strictQuestion(raw: unknown): string {
  return String(raw ?? "").replace(/\s+/g, " ").trim().slice(0, QUESTION_MAX);
}

type KbRow = {
  id: string;
  topic: string;
  title: string;
  body: string;
  body_hi: string;
  triggers: string;
  rank: number;
};

/**
 * Ask a cheap LLM to phrase the KB answer. Returns null on any failure so
 * the caller falls back to the KB row verbatim — a missing key or a dead
 * provider must never turn into a failed support request.
 */
async function llmPhrase(
  question: string,
  kb: KbRow,
  lang: string,
): Promise<string | null> {
  const groq = Deno.env.get("GROQ_API_KEY");
  const gemini = Deno.env.get("GEMINI_API_KEY");
  const openrouter = Deno.env.get("OPENROUTER_API_KEY");
  const context = lang === "hi" && kb.body_hi ? kb.body_hi : kb.body;

  const system = lang === "hi"
    ? "Tum Dizzy app ke support assistant ho. Chhote, simple Hinglish jawab do. Kabhi technical shabd use mat karo. 3 line se zyada mat likho. Agar context kaafi nahi hai to sirf itna kaho ki hum aapko human se connect kar rahe hain."
    : "You are the Dizzy app support assistant. Reply in short, simple English. Never use technical jargon. Keep it under 3 lines. If the context is not enough, just say you are connecting them to a human.";
  const user = lang === "hi"
    ? `Sawaal: ${question}\n\nApp ka jawab (context): ${context}`
    : `Question: ${question}\n\nApp knowledge (context): ${context}`;

  const prompt = `${system}\n\n${user}`;

  try {
    if (groq) {
      const r = await fetch("https://api.groq.com/openai/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${groq}`,
        },
        body: JSON.stringify({
          model: "llama-3.3-70b-versatile",
          messages: [{ role: "user", content: prompt }],
          max_tokens: 200,
          temperature: 0.2,
        }),
        signal: AbortSignal.timeout(12000),
      });
      if (r.ok) {
        const d = await r.json();
        const t = d?.choices?.[0]?.message?.content;
        if (typeof t === "string" && t.trim()) return t.trim();
      }
      return null;
    }
    if (gemini) {
      const r = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${gemini}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { maxOutputTokens: 200, temperature: 0.2 },
          }),
          signal: AbortSignal.timeout(12000),
        },
      );
      if (r.ok) {
        const d = await r.json();
        const t = d?.candidates?.[0]?.content?.parts?.[0]?.text;
        if (typeof t === "string" && t.trim()) return t.trim();
      }
      return null;
    }
    if (openrouter) {
      const r = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${openrouter}`,
        },
        body: JSON.stringify({
          model: "meta-llama/llama-3.3-70b-instruct",
          messages: [{ role: "user", content: prompt }],
          max_tokens: 200,
          temperature: 0.2,
        }),
        signal: AbortSignal.timeout(12000),
      });
      if (r.ok) {
        const d = await r.json();
        const t = d?.choices?.[0]?.message?.content;
        if (typeof t === "string" && t.trim()) return t.trim();
      }
      return null;
    }
  } catch {
    // Provider down / timeout: fall through to the KB row.
  }
  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization")! } } },
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const question = strictQuestion(body?.question);
    const lang = strictLang(body?.lang);
    const trail = strictTrail(body?.trail);
    const codes = Array.isArray(body?.codes)
      ? (body!.codes as unknown[]).map((c) => strictToken(c, 32)).filter(Boolean)
      : [];

    if (question === "") {
      return json({ tier: "none", answer: "", matched_id: "", score: 0, suggest_ticket: true });
    }

    // Rank the server KB (SECURITY DEFINER; callable by the signed-in user).
    const { data: rows, error } = await supabase.rpc("support_kb_lookup", {
      p_query: question,
      p_limit: 5,
    });
    if (error) throw error;

    const list = (Array.isArray(rows) ? rows : []) as KbRow[];
    const best = list.length > 0 ? list[0] : null;
    const score = best ? Number(best.rank) || 0 : 0;

    // Weak match = no confident answer; offer a ticket instead of guessing.
    if (!best || score < 0.25) {
      await supabase.rpc("support_log_answer", {
        p_question: question,
        p_matched: "",
        p_score: score,
        p_lang: lang,
        p_tier: "none",
        p_escalated: true,
      }).then(() => {}, () => {});
      return json({
        tier: "none",
        answer: "",
        matched_id: "",
        score,
        suggest_ticket: true,
        trail,
        codes,
      });
    }

    const kbAnswer = lang === "hi" && best.body_hi ? best.body_hi : best.body;
    const phrased = await llmPhrase(question, best, lang);
    const answer = phrased ?? kbAnswer;

    await supabase.rpc("support_log_answer", {
      p_question: question,
      p_matched: best.id,
      p_score: score,
      p_lang: lang,
      p_tier: phrased ? "llm" : "kb",
      p_escalated: false,
    }).then(() => {}, () => {});

    return json({
      tier: phrased ? "llm" : "kb",
      answer,
      matched_id: best.id,
      topic: best.topic,
      score,
      suggest_ticket: false,
      trail,
      codes,
    });
  } catch (e) {
    // Never fail a support request: an empty answer tells the app to offer
    // the ticket path, which is the correct degradation.
    return json({ tier: "none", answer: "", suggest_ticket: true, error: String(e) });
  }
});