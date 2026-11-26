import { readFile } from "node:fs/promises";
import { join } from "node:path";

const lineSupportUrl = "https://lin.ee/pzygyU4";
const rateBuckets = new Map();

// ログに出してよい固定文だけを持つ例外。利用者の本文やAIの返答を含めない。
class SafeError extends Error {}

function fallback(message = "\u73fe\u5728AI\u30b5\u30dd\u30fc\u30c8\u306b\u63a5\u7d9a\u3067\u304d\u307e\u305b\u3093\u3002LINE\u30b5\u30dd\u30fc\u30c8\u3078\u3054\u76f8\u8ac7\u304f\u3060\u3055\u3044\u3002") {
  return { answer: message, resolved: false, escalationUrl: lineSupportUrl };
}

function clientAddress(request) {
  const forwarded = String(request.headers["x-forwarded-for"] || "").split(",")[0].trim();
  return String(request.headers["x-vercel-forwarded-for"] || forwarded || request.socket?.remoteAddress || "unknown");
}

function isRateLimited(address, now = Date.now()) {
  const windowMs = 10 * 60 * 1000;
  const recent = (rateBuckets.get(address) || []).filter((stamp) => now - stamp < windowMs);
  if (recent.length >= 15) return true;
  recent.push(now);
  rateBuckets.set(address, recent);
  return false;
}

async function askGemini(question, history, manual) {
  const apiKey = process.env.GEMINI_API_KEY || "";
  if (!apiKey) return fallback();
  const model = process.env.SUPPORT_GEMINI_MODEL || "gemini-3.5-flash-lite";
  const safeHistory = Array.isArray(history)
    ? history.slice(-6).flatMap((item) => {
        if (!item || !["user", "assistant"].includes(item.role)) return [];
        const content = String(item.content || "").trim().slice(0, 500);
        return content ? [{ role: item.role, content }] : [];
      })
    : [];
  const prompt = `You are the official support assistant for Stellise. Answer in natural, concise Japanese using only the support manual below. Never guess. If the manual cannot fully answer the question, set resolved to false and recommend LINE support. Return JSON only: {"answer":"...","resolved":true or false}.\n\n<manual>\n${manual}\n</manual>\n\nRecent conversation:\n${JSON.stringify(safeHistory)}\n\nQuestion:\n${question}`;
  const upstream = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { responseMimeType: "application/json" }
    }),
    signal: AbortSignal.timeout(13_000)
  });
  if (!upstream.ok) throw new SafeError(`Gemini returned ${upstream.status}`);
  const result = await upstream.json();
  const text = result?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new SafeError("Gemini returned an empty response");
  const parsed = JSON.parse(text);
  const answer = String(parsed.answer || "").trim().slice(0, 800);
  if (!answer) throw new SafeError("Gemini returned an empty answer");
  const resolved = parsed.resolved === true;
  return { answer, resolved, escalationUrl: resolved ? null : lineSupportUrl };
}

export default async function handler(request, response) {
  response.setHeader("Cache-Control", "no-store");
  if (request.method !== "POST") {
    response.setHeader("Allow", "POST");
    return response.status(405).json({ error: "Method not allowed" });
  }
  if (isRateLimited(clientAddress(request))) {
    return response.status(429).json(fallback("\u5c11\u3057\u6642\u9593\u3092\u304a\u3044\u3066\u304b\u3089\u3001\u3082\u3046\u4e00\u5ea6\u304a\u8a66\u3057\u304f\u3060\u3055\u3044\u3002"));
  }
  try {
    const body = typeof request.body === "string" ? JSON.parse(request.body) : request.body;
    const question = String(body?.question || "").trim();
    if (!question || question.length > 500) {
      return response.status(400).json({ error: "\u8cea\u554f\u306f1\u301c500\u6587\u5b57\u3067\u5165\u529b\u3057\u3066\u304f\u3060\u3055\u3044\u3002" });
    }
    const manual = await readFile(join(process.cwd(), "docs", "support-manual.md"), "utf8");
    return response.status(200).json(await askGemini(question, body?.history, manual));
  } catch (error) {
    // 例外のmessageにはJSON.parseの失敗で本文やAI返答が混ざるため、自前の固定文以外は名前だけ記録する。
    console.error("Support ChatBot error:", error instanceof SafeError ? error.message : (error?.name || "Error"));
    return response.status(503).json(fallback());
  }
}
