/**
 * Tars extension for pi. Projects pi's lifecycle events onto the same payload shape
 * ~/.tars/bin/tars-hook-pi already reads from Claude Code, so every state decision
 * stays in one place (Mac/hook.py).
 *
 * Installed by Mac/install-hooks.py into ~/.pi/agent/extensions/tars.ts.
 */
import { spawn } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

const HOOK = join(homedir(), ".tars", "bin", "tars-hook-pi")

function send(payload) {
  try {
    const child = spawn(HOOK, [], { stdio: ["pipe", "ignore", "ignore"] })
    child.on("error", () => {})
    child.stdin.on("error", () => {})
    child.stdin.end(JSON.stringify(payload))
  } catch (_) {}
}

function sessionId(ctx) {
  try {
    return ctx.sessionManager.getSessionId() || "unknown"
  } catch (_) {
    return "unknown"
  }
}

function assistantText(message) {
  if (!message || message.role !== "assistant") return undefined
  if (typeof message.content === "string") return message.content
  if (!Array.isArray(message.content)) return undefined
  const text = message.content
    .filter((part) => part && part.type === "text" && typeof part.text === "string")
    .map((part) => part.text)
    .join("")
  return text || undefined
}

export default function (pi) {
  const lastText = new Map() // session id -> last assistant message, bounded by live sessions

  pi.on("session_start", (_event, ctx) => {
    send({ hook_event_name: "SessionStart", session_id: sessionId(ctx) })
  })

  pi.on("before_agent_start", (event, ctx) => {
    send({ hook_event_name: "UserPromptSubmit", session_id: sessionId(ctx), prompt: event.prompt })
  })

  pi.on("tool_call", (event, ctx) => {
    send({
      hook_event_name: "PreToolUse",
      session_id: sessionId(ctx),
      tool_name: event.toolName,
      tool_input: event.input,
    })
  })

  pi.on("message_end", (event, ctx) => {
    const text = assistantText(event && event.message)
    if (text) lastText.set(sessionId(ctx), text)
  })

  pi.on("agent_end", (_event, ctx) => {
    const id = sessionId(ctx)
    send({ hook_event_name: "Stop", session_id: id, last_assistant_message: lastText.get(id) })
    lastText.delete(id)
  })

  pi.on("session_shutdown", (_event, ctx) => {
    const id = sessionId(ctx)
    send({ hook_event_name: "SessionEnd", session_id: id })
    lastText.delete(id)
  })
}
