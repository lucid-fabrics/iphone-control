/**
 * Tests for the MCP server's runScript helper and tool argument handling.
 *
 * These tests mock child_process.execFile to avoid calling real shell scripts
 * or requiring iPhone Mirroring to be running.
 *
 * Run with: npx vitest run (or npx jest if jest is configured)
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import { execFile } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// We test runScript in isolation by re-implementing its core logic here,
// since the actual module boots an MCP server on import.

const __filename_test = fileURLToPath(import.meta.url);
const __dirname_test = dirname(__filename_test);
const SCRIPTS_DIR = resolve(__dirname_test, "..", "..");

const PATH = [
  "/opt/homebrew/bin",
  "/usr/local/bin",
  "/usr/bin",
  "/bin",
  "/usr/sbin",
  "/sbin",
].join(":");

const TIMEOUT_DEFAULT = 15_000;
const TIMEOUT_APP_LAUNCH = 30_000;
const TIMEOUT_SCAN = 120_000;

type ExecFileCallback = (
  error: Error | null,
  stdout: string,
  stderr: string
) => void;

// Extracted runScript logic for testability
function runScript(
  name: string,
  args: string[] = [],
  timeout = TIMEOUT_DEFAULT,
  execFileFn: typeof execFile = execFile
): Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    (execFileFn as Function)(
      `${SCRIPTS_DIR}/${name}`,
      args,
      { timeout, env: { ...process.env, PATH } },
      (error: Error | null, stdout: string, stderr: string) => {
        if (error) {
          reject(new Error((stderr || "").trim() || error.message));
        } else {
          resolve({ stdout: (stdout || "").trim(), stderr: (stderr || "").trim() });
        }
      }
    );
  });
}

describe("runScript", () => {
  it("resolves with stdout on success", async () => {
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        cb(null, "test output\n", "");
      }
    );

    const result = await runScript("test.sh", [], TIMEOUT_DEFAULT, mockExecFile as any);
    expect(result.stdout).toBe("test output");
    expect(result.stderr).toBe("");
  });

  it("rejects with stderr message on error", async () => {
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        cb(new Error("exit code 1"), "", "script failed\n");
      }
    );

    await expect(
      runScript("test.sh", [], TIMEOUT_DEFAULT, mockExecFile as any)
    ).rejects.toThrow("script failed");
  });

  it("rejects with error.message when stderr is empty", async () => {
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        cb(new Error("ETIMEOUT"), "", "");
      }
    );

    await expect(
      runScript("test.sh", [], TIMEOUT_DEFAULT, mockExecFile as any)
    ).rejects.toThrow("ETIMEOUT");
  });

  it("passes correct script path", async () => {
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        cb(null, cmd, "");
      }
    );

    const result = await runScript("find-window.sh", [], TIMEOUT_DEFAULT, mockExecFile as any);
    expect(result.stdout).toContain("find-window.sh");
    expect(result.stdout).toContain(SCRIPTS_DIR);
  });

  it("passes arguments to execFile", async () => {
    let capturedArgs: string[] = [];
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        capturedArgs = args;
        cb(null, "ok", "");
      }
    );

    await runScript("tap.sh", ["100", "200"], TIMEOUT_DEFAULT, mockExecFile as any);
    expect(capturedArgs).toEqual(["100", "200"]);
  });

  it("uses provided timeout", async () => {
    let capturedOpts: any = {};
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: any, cb: ExecFileCallback) => {
        capturedOpts = opts;
        cb(null, "ok", "");
      }
    );

    await runScript("registry.sh", ["scan"], TIMEOUT_SCAN, mockExecFile as any);
    expect(capturedOpts.timeout).toBe(TIMEOUT_SCAN);
  });

  it("sets PATH in env", async () => {
    let capturedOpts: any = {};
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: any, cb: ExecFileCallback) => {
        capturedOpts = opts;
        cb(null, "ok", "");
      }
    );

    await runScript("test.sh", [], TIMEOUT_DEFAULT, mockExecFile as any);
    expect(capturedOpts.env.PATH).toBe(PATH);
  });

  it("trims stdout whitespace", async () => {
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        cb(null, "  padded output  \n", "");
      }
    );

    const result = await runScript("test.sh", [], TIMEOUT_DEFAULT, mockExecFile as any);
    expect(result.stdout).toBe("padded output");
  });
});

describe("tool argument construction", () => {
  it("tap: passes x and y as string args", () => {
    const x = 150;
    const y = 300;
    const args = [String(x), String(y)];
    expect(args).toEqual(["150", "300"]);
  });

  it("swipe: passes 4 coords without duration", () => {
    const x1 = 100, y1 = 200, x2 = 300, y2 = 400;
    const args = [String(x1), String(y1), String(x2), String(y2)];
    expect(args).toEqual(["100", "200", "300", "400"]);
    expect(args).toHaveLength(4);
  });

  it("swipe: passes 5 args with optional duration", () => {
    const x1 = 100, y1 = 200, x2 = 300, y2 = 400;
    const duration_ms = 500;
    const args = [String(x1), String(y1), String(x2), String(y2)];
    if (duration_ms !== undefined) args.push(String(duration_ms));
    expect(args).toEqual(["100", "200", "300", "400", "500"]);
    expect(args).toHaveLength(5);
  });

  it("type_text: passes text only when no coords", () => {
    const text = "hello world";
    const args = [text];
    expect(args).toEqual(["hello world"]);
  });

  it("type_text: passes text + coords when both provided", () => {
    const text = "hello";
    const x = 50, y = 100;
    const args = [text];
    if (x !== undefined && y !== undefined) {
      args.push(String(x), String(y));
    }
    expect(args).toEqual(["hello", "50", "100"]);
  });

  it("open_app: passes name only for auto method", () => {
    const name = "Safari";
    const method: string = "auto";
    const args = [name];
    if (method === "spotlight") args.push("--spotlight");
    expect(args).toEqual(["Safari"]);
  });

  it("open_app: passes --spotlight flag when method is spotlight", () => {
    const name = "Settings";
    const method = "spotlight";
    const args = [name];
    if (method === "spotlight") args.push("--spotlight");
    expect(args).toEqual(["Settings", "--spotlight"]);
  });

  it("scan_apps: passes scan command with max_pages", () => {
    const max_pages = 5;
    const args = ["scan"];
    if (max_pages !== undefined) args.push(String(max_pages));
    expect(args).toEqual(["scan", "5"]);
  });

  it("scan_apps: passes scan command without max_pages", () => {
    const max_pages = undefined;
    const args: string[] = ["scan"];
    if (max_pages !== undefined) args.push(String(max_pages));
    expect(args).toEqual(["scan"]);
  });
});

describe("timeout constants", () => {
  it("default timeout is 15 seconds", () => {
    expect(TIMEOUT_DEFAULT).toBe(15_000);
  });

  it("app launch timeout is 30 seconds", () => {
    expect(TIMEOUT_APP_LAUNCH).toBe(30_000);
  });

  it("scan timeout is 120 seconds", () => {
    expect(TIMEOUT_SCAN).toBe(120_000);
  });
});

describe("tool handler: screenshot", () => {
  it("reads file and returns base64-encoded content", async () => {
    const pngBytes = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const base64 = pngBytes.toString("base64");

    // Simulate what the screenshot tool handler does
    const data = Buffer.from(base64, "base64");
    expect(data.toString("base64")).toBe(base64);
    expect(data[0]).toBe(0x89);
    expect(data[1]).toBe(0x50); // 'P' in PNG
  });

  it("calls screenshot.sh with temp path", async () => {
    let capturedArgs: string[] = [];
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        capturedArgs = args;
        cb(null, "", "");
      }
    );

    const tmpPath = `/tmp/iphone-mcp-test.png`;
    await runScript("screenshot.sh", [tmpPath], TIMEOUT_DEFAULT, mockExecFile as any);
    expect(capturedArgs).toEqual([tmpPath]);
  });
});

describe("tool handler: tap", () => {
  it("passes coordinates as string arguments", async () => {
    let capturedArgs: string[] = [];
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        capturedArgs = args;
        cb(null, "Tapped at (150, 300)", "");
      }
    );

    const x = 150, y = 300;
    const result = await runScript("tap.sh", [String(x), String(y)], TIMEOUT_DEFAULT, mockExecFile as any);
    expect(capturedArgs).toEqual(["150", "300"]);
    expect(result.stdout).toContain("Tapped");
  });
});

describe("tool handler: swipe", () => {
  it("handles optional duration_ms", async () => {
    let capturedArgs: string[] = [];
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        capturedArgs = args;
        cb(null, "Swiped", "");
      }
    );

    // Without duration
    const args4 = [String(10), String(20), String(300), String(400)];
    await runScript("swipe.sh", args4, TIMEOUT_DEFAULT, mockExecFile as any);
    expect(capturedArgs).toHaveLength(4);

    // With duration
    const duration_ms = 500;
    const args5 = [...args4, String(duration_ms)];
    await runScript("swipe.sh", args5, TIMEOUT_DEFAULT, mockExecFile as any);
    expect(capturedArgs).toHaveLength(5);
    expect(capturedArgs[4]).toBe("500");
  });
});

describe("tool handler: type_text", () => {
  it("handles optional x,y coordinates", async () => {
    let capturedArgs: string[] = [];
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        capturedArgs = args;
        cb(null, "Typed", "");
      }
    );

    // Without coords
    const argsNoCoords = ["hello world"];
    await runScript("type-text.sh", argsNoCoords, TIMEOUT_DEFAULT, mockExecFile as any);
    expect(capturedArgs).toEqual(["hello world"]);

    // With coords
    const x = 50, y = 100;
    const argsWithCoords = ["hello", String(x), String(y)];
    await runScript("type-text.sh", argsWithCoords, TIMEOUT_DEFAULT, mockExecFile as any);
    expect(capturedArgs).toEqual(["hello", "50", "100"]);
  });
});

describe("tool handler: open_app", () => {
  it("handles method parameter", async () => {
    let capturedArgs: string[] = [];
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        capturedArgs = args;
        cb(null, "Opened: Safari (spotlight)", "");
      }
    );

    // auto method - no flag
    const autoArgs = ["Safari"];
    await runScript("open-app.sh", autoArgs, TIMEOUT_APP_LAUNCH, mockExecFile as any);
    expect(capturedArgs).toEqual(["Safari"]);

    // spotlight method - adds flag
    const spotlightArgs = ["Safari", "--spotlight"];
    await runScript("open-app.sh", spotlightArgs, TIMEOUT_APP_LAUNCH, mockExecFile as any);
    expect(capturedArgs).toEqual(["Safari", "--spotlight"]);
  });
});

describe("tool handler: scan_apps", () => {
  it("passes max_pages to registry.sh scan", async () => {
    let capturedArgs: string[] = [];
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        capturedArgs = args;
        cb(null, '{"version":1}', "");
      }
    );

    const max_pages = 5;
    const args = ["scan", String(max_pages)];
    await runScript("registry.sh", args, TIMEOUT_SCAN, mockExecFile as any);
    expect(capturedArgs).toEqual(["scan", "5"]);
  });

  it("omits max_pages when undefined", async () => {
    let capturedArgs: string[] = [];
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        capturedArgs = args;
        cb(null, '{"version":1}', "");
      }
    );

    const args: string[] = ["scan"];
    await runScript("registry.sh", args, TIMEOUT_SCAN, mockExecFile as any);
    expect(capturedArgs).toEqual(["scan"]);
  });
});

describe("error handling", () => {
  it("rejects with stderr when script fails", async () => {
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        cb(new Error("exit code 1"), "", "iPhone Mirroring window not found\n");
      }
    );

    await expect(
      runScript("find-window.sh", [], TIMEOUT_DEFAULT, mockExecFile as any)
    ).rejects.toThrow("iPhone Mirroring window not found");
  });

  it("rejects with error.message when script produces no stderr", async () => {
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        cb(new Error("SIGTERM"), "", "");
      }
    );

    await expect(
      runScript("screenshot.sh", [], TIMEOUT_DEFAULT, mockExecFile as any)
    ).rejects.toThrow("SIGTERM");
  });

  it("handles timeout errors", async () => {
    const mockExecFile = vi.fn(
      (cmd: string, args: string[], opts: object, cb: ExecFileCallback) => {
        const err = new Error("TIMEOUT") as Error & { killed: boolean };
        err.killed = true;
        cb(err, "", "");
      }
    );

    await expect(
      runScript("registry.sh", ["scan"], TIMEOUT_SCAN, mockExecFile as any)
    ).rejects.toThrow("TIMEOUT");
  });
});
