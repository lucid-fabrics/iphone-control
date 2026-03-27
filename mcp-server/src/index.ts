#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile, unlink } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { z } from "zod";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Scripts live in the repo root (one level up from mcp-server/dist/)
const SCRIPTS_DIR = resolve(__dirname, "..", "..");

const PATH = [
  "/opt/homebrew/bin",
  "/usr/local/bin",
  "/usr/bin",
  "/bin",
  "/usr/sbin",
  "/sbin",
].join(":");

// Timeouts (ms)
const TIMEOUT_DEFAULT = 15_000;
const TIMEOUT_APP_LAUNCH = 30_000;
const TIMEOUT_SCAN = 120_000;

function runScript(
  name: string,
  args: string[] = [],
  timeout = TIMEOUT_DEFAULT
): Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    execFile(
      `${SCRIPTS_DIR}/${name}`,
      args,
      { timeout, env: { ...process.env, PATH } },
      (error, stdout, stderr) => {
        if (error) {
          if (error.killed) {
            reject(new Error(`${name} timed out after ${timeout}ms`));
          } else {
            const detail = stderr.trim() || error.message;
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const code = (error as any).code;
            reject(new Error(typeof code === "number" ? `${name} exited ${code}: ${detail}` : detail));
          }
        } else {
          resolve({ stdout: stdout.trim(), stderr: stderr.trim() });
        }
      }
    );
  });
}

const server = new McpServer({
  name: "iphone-control",
  version: "1.0.0",
});

// find_window
server.tool("find_window", "Locate the iPhone Mirroring window. Returns JSON with window bounds and content bounds (iOS screen area inside bezel).", {}, async () => {
  const { stdout } = await runScript("find-window.sh");
  return { content: [{ type: "text", text: stdout }] };
});

// screenshot
server.tool("screenshot", "Take a screenshot of the iPhone screen. Returns the image directly.", {}, async () => {
  const tmpPath = `/tmp/iphone-mcp-${randomUUID()}.png`;
  try {
    await runScript("screenshot.sh", [tmpPath]);
    const data = await readFile(tmpPath);
    return {
      content: [
        {
          type: "image",
          data: data.toString("base64"),
          mimeType: "image/png",
        },
      ],
    };
  } finally {
    unlink(tmpPath).catch(() => {});
  }
});

// tap
server.tool(
  "tap",
  "Tap at coordinates relative to the iPhone content area.",
  { x: z.number().int().describe("X coordinate"), y: z.number().int().describe("Y coordinate") },
  async ({ x, y }) => {
    const { stdout } = await runScript("tap.sh", [String(x), String(y)]);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// swipe
server.tool(
  "swipe",
  "Swipe from (x1,y1) to (x2,y2) on the iPhone content area.",
  {
    x1: z.number().int().describe("Start X"),
    y1: z.number().int().describe("Start Y"),
    x2: z.number().int().describe("End X"),
    y2: z.number().int().describe("End Y"),
    duration_ms: z.number().int().min(1).optional().describe("Swipe duration in ms (default 300)"),
  },
  async ({ x1, y1, x2, y2, duration_ms }) => {
    const args = [String(x1), String(y1), String(x2), String(y2)];
    if (duration_ms !== undefined) args.push(String(duration_ms));
    const { stdout } = await runScript("swipe.sh", args);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// type_text
server.tool(
  "type_text",
  "Type text into the iPhone. Optionally tap a field first.",
  {
    text: z.string().min(1).describe("Text to type"),
    x: z.number().int().optional().describe("X coordinate to tap before typing"),
    y: z.number().int().optional().describe("Y coordinate to tap before typing"),
  },
  async ({ text, x, y }) => {
    if ((x === undefined) !== (y === undefined)) {
      throw new Error("x and y must both be provided together or both omitted");
    }
    const args = [text];
    if (x !== undefined && y !== undefined) {
      args.push(String(x), String(y));
    }
    const { stdout } = await runScript("type-text.sh", args);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// open_app
server.tool(
  "open_app",
  "Open an app on the iPhone by name. Uses registry (fast, ~0.5s) with Spotlight fallback (~1.5s). Run scan_apps first to populate the registry.",
  {
    name: z.string().min(1).describe("App name to open (e.g. 'Settings', 'Safari')"),
    method: z.enum(["auto", "spotlight"]).optional().describe("Launch method: 'auto' (registry→spotlight fallback, default) or 'spotlight' (force Spotlight)"),
  },
  async ({ name, method }) => {
    const args = [name];
    if (method === "spotlight") args.push("--spotlight");
    const { stdout } = await runScript("open-app.sh", args, TIMEOUT_APP_LAUNCH);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// home
server.tool("home", "Go to the iPhone home screen via the View menu.", {}, async () => {
  const { stdout } = await runScript("iphone-control.sh", ["home"]);
  return { content: [{ type: "text", text: stdout }] };
});

// app_switcher
server.tool("app_switcher", "Open the iPhone app switcher via the View menu.", {}, async () => {
  const { stdout } = await runScript("iphone-control.sh", ["app-switcher"]);
  return { content: [{ type: "text", text: stdout }] };
});

// spotlight
server.tool("spotlight", "Open iPhone Spotlight search via the View menu.", {}, async () => {
  const { stdout } = await runScript("iphone-control.sh", ["spotlight"]);
  return { content: [{ type: "text", text: stdout }] };
});

// status
server.tool("status", "Check if iPhone Mirroring is connected and active.", {}, async () => {
  const { stdout } = await runScript("status.sh");
  return { content: [{ type: "text", text: stdout }] };
});

// scan_apps (replaces both scan_apps and map_apps — they were identical)
server.tool(
  "scan_apps",
  "Scan all iPhone home screen pages via OCR and save results to persistent registry. This populates the app registry used by open_app for fast launches. Returns full registry JSON with app names, pages, and coordinates.",
  {
    max_pages: z.number().int().min(1).optional().describe("Max home screen pages to scan (default 10)"),
  },
  async ({ max_pages }) => {
    const args = ["scan"];
    if (max_pages !== undefined) args.push(String(max_pages));
    const { stdout } = await runScript("registry.sh", args, TIMEOUT_SCAN);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// registry_invalidate
server.tool("registry_invalidate", "Delete the cached app registry, forcing a full rescan on the next scan_apps or open_app call.", {}, async () => {
  const { stdout } = await runScript("registry.sh", ["invalidate"]);
  return { content: [{ type: "text", text: stdout }] };
});

// list_apps
server.tool(
  "list_apps",
  "List all apps from the cached registry. Returns the saved registry data without rescanning. Run scan_apps first if no registry exists.",
  {},
  async () => {
    const { stdout } = await runScript("registry.sh", ["list"]);
    return { content: [{ type: "text", text: stdout }] };
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
