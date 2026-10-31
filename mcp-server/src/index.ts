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
server.tool("find_window", "Locate the iPhone Mirroring window. Returns JSON with window bounds and content bounds (iOS screen area inside bezel). Bounds are global Mac display points and can be negative when the window sits on a display left of or above the primary one.", {}, async () => {
  const { stdout } = await runScript("find-window.sh");
  return { content: [{ type: "text", text: stdout }] };
});

// screenshot
server.tool("screenshot", "Take a screenshot of the iPhone screen. Returns a PNG whose pixel dimensions equal the tap/swipe coordinate space (1 image pixel = 1 coordinate unit, on any display or Retina scale).", {}, async () => {
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
  "Tap at coordinates relative to the iPhone content area. Coordinates are content points, identical to screenshot pixel coordinates.",
  { x: z.number().int().describe("X coordinate"), y: z.number().int().describe("Y coordinate") },
  async ({ x, y }) => {
    const { stdout } = await runScript("tap.sh", [String(x), String(y)]);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// swipe
server.tool(
  "swipe",
  "Swipe from (x1,y1) to (x2,y2) on the iPhone content area. Coordinates are content points, identical to screenshot pixel coordinates.",
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

// tap_text
server.tool(
  "tap_text",
  "OCR the screen and tap the text matching the query (case-insensitive; exact match beats substring). PREFER this over tap with raw coordinates whenever the target shows text - OCR-derived centers do not drift. On no match it returns an error listing every string currently on screen; use that to decide whether to scroll and retry.",
  {
    text: z.string().min(1).describe("Text to find and tap"),
    index: z.number().int().min(1).optional().describe("When several matches, tap the Nth from the top (default 1)"),
  },
  async ({ text, index }) => {
    const args = [text];
    if (index !== undefined) args.push("--index", String(index));
    const { stdout } = await runScript("tap-text.sh", args);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// tap_verify
server.tool(
  "tap_verify",
  "Tap and CONFIRM it worked, retrying once on failure. Default check: the screen visibly changed. Or pass expect (text that must appear) / gone (text that must disappear). Use this instead of tap for any tap whose success matters - silently missed taps are the top failure mode of automated flows.",
  {
    x: z.number().int().describe("X coordinate"),
    y: z.number().int().describe("Y coordinate"),
    expect: z.string().optional().describe("Text that must be on screen after the tap"),
    gone: z.string().optional().describe("Text that must have left the screen after the tap"),
  },
  async ({ x, y, expect, gone }) => {
    if (expect !== undefined && gone !== undefined) {
      throw new Error("pass either expect or gone, not both");
    }
    const args = [String(x), String(y)];
    if (expect !== undefined) args.push("--expect", expect);
    if (gone !== undefined) args.push("--gone", gone);
    const { stdout } = await runScript("tap-verify.sh", args, TIMEOUT_APP_LAUNCH);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// read_screen
server.tool(
  "read_screen",
  "Read all text currently on the iPhone screen with tappable center coordinates. This is the inspection channel (there is no accessibility tree through mirroring). Lines below OCR confidence 0.6 are already filtered out. Format: 'cx,cy  text' per line, coordinates ready to pass to tap.",
  {
    grep: z.string().optional().describe("Only lines whose text matches this case-insensitive regex"),
    all: z.boolean().optional().describe("Read the WHOLE scrolling list, not just the visible screen: scrolls through it, OCRs each page, stitches them into one de-duplicated top-to-bottom list, then scrolls back. Use this instead of repeated scroll + read_screen. Output is 'y_abs  text' where y_abs is the position in the list, NOT a tap coordinate: act on a row with scroll_to(text, tap=true). Chrome that never scrolls (status bar, nav title) is listed as 'fixed'."),
    from_top: z.boolean().optional().describe("With all: scroll to the top of the list first (default: start from the current position)"),
    max_pages: z.number().int().min(1).max(40).optional().describe("With all: stop after this many pages (default 15)"),
  },
  async ({ grep, all, from_top, max_pages }) => {
    const args: string[] = [];
    if (grep !== undefined) args.push("--grep", grep);
    if (all) {
      if (from_top) args.push("--from-top");
      if (max_pages !== undefined) args.push("--max", String(max_pages));
      const { stdout } = await runScript("read-all.sh", args, TIMEOUT_SCAN);
      return { content: [{ type: "text", text: stdout || "(no text detected in the list)" }] };
    }
    const { stdout } = await runScript("read.sh", args);
    return { content: [{ type: "text", text: stdout || "(no text detected on screen)" }] };
  }
);

// wait_for
server.tool(
  "wait_for",
  "Wait for a screen condition instead of sleeping a guessed duration - faster on quick transitions AND reliable on slow ones. Conditions: text (string appears), gone (string disappears), still (animations settled). Use after every navigation or app launch before reading or tapping.",
  {
    condition: z.enum(["text", "gone", "still"]).describe("What to wait for"),
    text: z.string().optional().describe("The string to watch for (required for text/gone)"),
    timeout_s: z.number().min(0.5).max(120).optional().describe("Give up after this many seconds (default 10)"),
  },
  async ({ condition, text, timeout_s }) => {
    if (condition !== "still" && !text) {
      throw new Error(`condition '${condition}' requires text`);
    }
    const args: string[] = condition === "still" ? ["still"] : [condition, text as string];
    if (timeout_s !== undefined) args.push("--timeout", String(timeout_s));
    const { stdout } = await runScript("wait.sh", args, (timeout_s ?? 10) * 1000 + 10_000);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// scroll
server.tool(
  "scroll",
  "Scroll the iPhone content. dy > 0 scrolls down (reveals lower content), dy < 0 scrolls up. NOTE: swipe does NOT scroll iOS lists through mirroring - this is the only way to scroll.",
  {
    dy: z.number().int().describe("Points to scroll; positive = down, negative = up"),
    x: z.number().int().optional().describe("Content X to scroll at (default: center)"),
    y: z.number().int().optional().describe("Content Y to scroll at (default: center)"),
  },
  async ({ dy, x, y }) => {
    if ((x === undefined) !== (y === undefined)) {
      throw new Error("x and y must both be provided together or both omitted");
    }
    const args = [String(dy)];
    if (x !== undefined && y !== undefined) args.push(String(x), String(y));
    const { stdout } = await runScript("scroll.sh", args);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// scroll_to
server.tool(
  "scroll_to",
  "Scroll until the given text is visible, then optionally tap it. Replaces the manual scroll-read-scroll loop.",
  {
    text: z.string().min(1).describe("Text to scroll to"),
    up: z.boolean().optional().describe("Scroll upward instead of down"),
    tap: z.boolean().optional().describe("Tap the text once found"),
    max_scrolls: z.number().int().min(1).optional().describe("Give up after this many scrolls (default 12)"),
  },
  async ({ text, up, tap, max_scrolls }) => {
    const args = [text];
    if (up) args.push("--up");
    if (tap) args.push("--tap");
    if (max_scrolls !== undefined) args.push("--max", String(max_scrolls));
    const { stdout } = await runScript("scroll-to.sh", args, TIMEOUT_SCAN);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// long_press
server.tool(
  "long_press",
  "Long press at coordinates (context menus, edit mode, text selection). Note: iOS context menus are NOT dismissed by Escape - tap dead space to close one.",
  {
    x: z.number().int().describe("X coordinate"),
    y: z.number().int().describe("Y coordinate"),
    hold_ms: z.number().int().min(100).max(5000).optional().describe("Hold duration in ms (default 800)"),
  },
  async ({ x, y, hold_ms }) => {
    const args = ["press", String(x), String(y)];
    if (hold_ms !== undefined) args.push(String(hold_ms));
    const { stdout } = await runScript("iphone-control.sh", args);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// double_tap
server.tool(
  "double_tap",
  "Double tap at coordinates (zoom toggle in photos/maps, word selection in text).",
  { x: z.number().int().describe("X coordinate"), y: z.number().int().describe("Y coordinate") },
  async ({ x, y }) => {
    const { stdout } = await runScript("iphone-control.sh", ["double-tap", String(x), String(y)]);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// press_key
server.tool(
  "press_key",
  "Send a key press to the iPhone. Keys: a-z, 0-9, return, tab, space, delete, escape, left, right, up, down. Modifiers combine (e.g. key 'a' with cmd = select all, 'v' with cmd = paste the Mac clipboard via Universal Clipboard). Characters are resolved against the Mac's active keyboard layout.",
  {
    key: z.string().min(1).describe("Key name or single character"),
    cmd: z.boolean().optional().describe("Hold Command"),
    shift: z.boolean().optional().describe("Hold Shift"),
    option: z.boolean().optional().describe("Hold Option"),
    control: z.boolean().optional().describe("Hold Control"),
  },
  async ({ key, cmd, shift, option, control }) => {
    const args = [key];
    if (cmd) args.push("--cmd");
    if (shift) args.push("--shift");
    if (option) args.push("--option");
    if (control) args.push("--control");
    const { stdout } = await runScript("key.sh", args);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// go_back
server.tool(
  "go_back",
  "Navigate back in the current iOS app. Taps the on-screen Back control when one exists (reliable), else falls back to the left-edge swipe gesture.",
  {},
  async () => {
    const { stdout } = await runScript("back.sh");
    return { content: [{ type: "text", text: stdout }] };
  }
);

// drag_icon
server.tool(
  "drag_icon",
  "Drag a home-screen icon: reorder the grid, or drop onto another icon to create/extend a folder (hover_ms >= 1200 for folder drops, default 300 for reorder). Enters jiggle mode safely and exits it afterwards. Multi-slot moves land short because the grid reflows - move one slot at a time and verify.",
  {
    x1: z.number().int().describe("Icon's current X"),
    y1: z.number().int().describe("Icon's current Y"),
    x2: z.number().int().describe("Target X"),
    y2: z.number().int().describe("Target Y"),
    hover_ms: z.number().int().min(0).max(5000).optional().describe("Hover before release: 300 = reorder (default), 1200+ = drop INTO icon (folder)"),
  },
  async ({ x1, y1, x2, y2, hover_ms }) => {
    const args = [String(x1), String(y1), String(x2), String(y2)];
    if (hover_ms !== undefined) args.push("--hover", String(hover_ms));
    const { stdout } = await runScript("drag-icon.sh", args, TIMEOUT_SCAN);
    return { content: [{ type: "text", text: stdout }] };
  }
);

// home
server.tool("home", "Go to the iPhone home screen (always lands on page 1; also escapes Today View).", {}, async () => {
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

// scan_apps (replaces both scan_apps and map_apps - they were identical)
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
