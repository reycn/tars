/**
 * Tars plugin for opencode. Projects opencode's bus events and hooks onto the same
 * payload shape ~/.tars/bin/tars-hook-opencode already reads from Claude Code, so
 * every state decision stays in one place (Mac/hook.py).
 *
 * Installed by Mac/install-hooks.py into <config>/opencode/plugin/tars.js.
 */
import { spawn } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

const HOOK = join(homedir(), ".tars", "bin", "tars-hook-opencode")

function send(payload) {
  try {
    const child = spawn(HOOK, [], { stdio: ["pipe", "ignore", "ignore"] })
    child.on("error", () => {})
    child.stdin.on("error", () => {})
    child.stdin.end(JSON.stringify(payload))
  } catch {}
}

export const TarsPlugin = async () => {
  // Both keyed by session id, so they stay bounded by the number of live sessions.
  const assistantMessage = new Map()
  const lastText = new Map()

  const forget = (sessionID) => {
    assistantMessage.delete(sessionID)
    lastText.delete(sessionID)
  }

  return {
    event: async ({ event }) => {
      const props = event.properties ?? {}
      switch (event.type) {
        case "session.created":
          send({ hook_event_name: "SessionStart", session_id: props.info?.id })
          break
        case "message.updated":
          if (props.info?.role === "assistant") assistantMessage.set(props.info.sessionID, props.info.id)
          break
        case "message.part.updated": {
          const part = props.part
          if (part?.type === "text" && assistantMessage.get(part.sessionID) === part.messageID) {
            lastText.set(part.sessionID, part.text)
          }
          break
        }
        case "session.idle":
          send({
            hook_event_name: "Stop",
            session_id: props.sessionID,
            last_assistant_message: lastText.get(props.sessionID),
          })
          lastText.delete(props.sessionID)
          break
        case "session.error":
          send({ hook_event_name: "StopFailure", session_id: props.sessionID })
          break
        case "session.deleted":
          send({ hook_event_name: "SessionEnd", session_id: props.info?.id })
          forget(props.info?.id)
          break
      }
    },
    "chat.message": async ({ sessionID }, { parts }) => {
      const prompt = (parts ?? []).filter((p) => p?.type === "text").map((p) => p.text).join(" ")
      send({ hook_event_name: "UserPromptSubmit", session_id: sessionID, prompt })
    },
    "tool.execute.before": async ({ tool, sessionID }, { args }) => {
      send({ hook_event_name: "PreToolUse", session_id: sessionID, tool_name: tool, tool_input: args })
    },
    "permission.ask": async (permission, output) => {
      if (output.status !== "ask") return
      send({
        hook_event_name: "PermissionRequest",
        session_id: permission.sessionID,
        message: permission.title,
        tool_name: permission.type,
        tool_input: permission.metadata,
      })
    },
  }
}

export default TarsPlugin
