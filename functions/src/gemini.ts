import type { Content, FunctionDeclaration, GoogleGenAI, Part, ThinkingLevel } from "@google/genai";
import { logger } from "firebase-functions";
import { HttpsError } from "firebase-functions/v2/https";
import { GEMINI_API_KEY } from "./config";

let client: GoogleGenAI | undefined;
/** Lazily loads the SDK so cold starts (and the emulator's function discovery) stay fast. */
export async function ai(): Promise<GoogleGenAI> {
  if (!client) {
    const { GoogleGenAI } = await import("@google/genai");
    client = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
  }
  return client;
}

/** Test hook: allows unit tests to inject a fake client. */
export function setClientForTests(c: unknown) {
  client = c as GoogleGenAI;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function isRetryable(e: unknown): boolean {
  const s = String((e as { status?: number })?.status ?? (e as Error)?.message ?? e);
  return /429|500|502|503|504|UNAVAILABLE|RESOURCE_EXHAUSTED|DEADLINE|fetch failed/i.test(s);
}

export async function withRetry<T>(fn: () => Promise<T>, tries = 3): Promise<T> {
  let last: unknown;
  for (let i = 0; i < tries; i++) {
    try {
      return await fn();
    } catch (e) {
      last = e;
      if (!isRetryable(e) || i === tries - 1) break;
      await sleep(600 * 2 ** i + Math.random() * 400);
    }
  }
  logger.error("gemini call failed", { error: String((last as Error)?.message ?? last) });
  throw new HttpsError("unavailable", "The stars are cloudy right now. Please try again in a moment.");
}

export interface JsonCall {
  model: string;
  system: string;
  parts: Part[];
  schema: object;
  maxOutputTokens?: number;
  temperature?: number;
  thinking?: ThinkingLevel;
}

/** Calls Gemini with structured JSON output and returns the parsed object. */
export async function generateJson<T>(c: JsonCall): Promise<T> {
  return withRetry(async () => {
    const res = await (await ai()).models.generateContent({
      model: c.model,
      contents: [{ role: "user", parts: c.parts }],
      config: {
        systemInstruction: c.system,
        responseMimeType: "application/json",
        responseJsonSchema: c.schema,
        temperature: c.temperature ?? 0.8,
        maxOutputTokens: c.maxOutputTokens ?? 4096,
        thinkingConfig: { thinkingLevel: c.thinking ?? ("LOW" as ThinkingLevel) },
      },
    });
    const text = res.text;
    if (!text) throw Object.assign(new Error("empty response"), { status: 503 });
    try {
      return JSON.parse(text) as T;
    } catch {
      // Malformed JSON is treated as retryable.
      throw Object.assign(new Error("invalid json"), { status: 503 });
    }
  });
}

export async function generateText(model: string, system: string, prompt: string, maxOutputTokens = 512): Promise<string> {
  return withRetry(async () => {
    const res = await (await ai()).models.generateContent({
      model,
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      config: {
        systemInstruction: system,
        temperature: 0.9,
        maxOutputTokens,
        thinkingConfig: { thinkingLevel: "MINIMAL" as ThinkingLevel },
      },
    });
    const t = res.text?.trim();
    if (!t) throw Object.assign(new Error("empty response"), { status: 503 });
    return t;
  });
}

export interface ChatTurnResult {
  text: string;
  toolCalls: { name: string; args: Record<string, unknown> }[];
}

/**
 * Runs one chat turn with optional function calling. `onTool` executes a tool
 * and returns its JSON result, which is fed back to the model.
 */
export async function chatWithTools(
  model: string,
  system: string,
  history: Content[],
  tools: FunctionDeclaration[],
  onTool: (name: string, args: Record<string, unknown>) => Promise<Record<string, unknown>>,
): Promise<ChatTurnResult> {
  const contents = [...history];
  const toolCalls: ChatTurnResult["toolCalls"] = [];
  for (let step = 0; step < 3; step++) {
    const res = await withRetry(async () =>
      (await ai()).models.generateContent({
        model,
        contents,
        config: {
          systemInstruction: system,
          temperature: 0.9,
          maxOutputTokens: 1024,
          tools: [{ functionDeclarations: tools }],
          thinkingConfig: { thinkingLevel: "LOW" as ThinkingLevel },
        },
      }),
    );
    const calls = res.functionCalls ?? [];
    if (calls.length === 0) {
      const text = res.text?.trim();
      if (!text) throw new HttpsError("unavailable", "No reply from the reader. Please try again.");
      return { text, toolCalls };
    }
    // Keep the model's turn (incl. thought signatures) exactly as returned.
    const modelContent = res.candidates?.[0]?.content;
    if (modelContent) contents.push(modelContent);
    const responses: Part[] = [];
    for (const call of calls) {
      const args = (call.args ?? {}) as Record<string, unknown>;
      toolCalls.push({ name: call.name ?? "", args });
      const out = await onTool(call.name ?? "", args);
      responses.push({ functionResponse: { id: call.id, name: call.name, response: out } });
    }
    contents.push({ role: "user", parts: responses });
  }
  throw new HttpsError("unavailable", "The reader got lost in the stars. Please try again.");
}
