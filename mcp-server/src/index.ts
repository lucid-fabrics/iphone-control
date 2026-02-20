#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { execFile } from "node:child_process";
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

function runScript(
  name: string,
  args: string[] = []
): Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    execFile(
      `${SCRIPTS_DIR}/${name}`,
      args,
      { timeout: 15_000, env: { ...process.env, PATH } },
      (error, stdout, stderr) => {
        if (error) {
          reject(new Error(stderr.trim() || error.message));
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
server.tool("find_window", "Locate the iPhone Mirroring window. Returns JSON with id, x, y, width, height.", {}, async () => {
  const { stdout } = await runScript("find-window.sh");
  return { content: [{ type: "text", text: stdout }] };
});

// screenshot
server.tool("screenshot", "Take a screenshot of the iPhone screen. Returns the image directly.", {}, async () => {
  const tmpPath = `/tmp/iphone-mcp-${Date.now()}.png`;
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
  "Tap at coordinates relative to the iPhone screen.",
  { x: z.number().describe("X coordinate"), y: z.number().describe("Y coordinate") },
  async ({ x, y }) => {
    const { stdout } = await runScript("tap.sh", [String(x), String(y)]);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// swipe
server.tool(
  "swipe",
  "Swipe from (x1,y1) to (x2,y2) on the iPhone screen.",
  {
    x1: z.number().describe("Start X"),
    y1: z.number().describe("Start Y"),
    x2: z.number().describe("End X"),
    y2: z.number().describe("End Y"),
    duration_ms: z.number().optional().describe("Swipe duration in ms (default 300)"),
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
    text: z.string().describe("Text to type"),
    x: z.number().optional().describe("X coordinate to tap before typing"),
    y: z.number().optional().describe("Y coordinate to tap before typing"),
  },
  async ({ text, x, y }) => {
    const args = [text];
    if (x !== undefined && y !== undefined) {
      args.push(String(x), String(y));
    }
    const { stdout } = await runScript("type-text.sh", args);
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
