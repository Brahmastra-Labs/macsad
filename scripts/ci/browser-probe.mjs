#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import {
  existsSync,
  lstatSync,
  readFileSync,
  realpathSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";

const expectedAdminState = "Draft staged in this browser only — no command was sent";

function stop(message) {
  throw new Error(message);
}

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) stop(`missing ${name}`);
  return process.argv[index + 1];
}

async function waitUntil(predicate, description, deadlineMilliseconds = 15_000) {
  const deadline = Date.now() + deadlineMilliseconds;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const value = await predicate();
      if (value) return value;
    } catch (error) {
      lastError = error;
    }
    await delay(100);
  }
  stop(`timed out waiting for ${description}${lastError ? `: ${lastError.message}` : ""}`);
}

class CdpClient {
  constructor(url) {
    if (typeof WebSocket !== "function") stop("Node runtime lacks the required WebSocket API");
    this.socket = new WebSocket(url);
    this.sequence = 0;
    this.pending = new Map();
    this.listeners = new Map();
  }

  async connect() {
    await new Promise((resolveConnection, rejectConnection) => {
      const timer = setTimeout(() => rejectConnection(new Error("CDP WebSocket open timeout")), 10_000);
      this.socket.addEventListener("open", () => {
        clearTimeout(timer);
        resolveConnection();
      }, { once: true });
      this.socket.addEventListener("error", () => {
        clearTimeout(timer);
        rejectConnection(new Error("CDP WebSocket failed to open"));
      }, { once: true });
    });
    this.socket.addEventListener("message", (event) => {
      const message = JSON.parse(String(event.data));
      if (message.id) {
        const pending = this.pending.get(message.id);
        if (!pending) return;
        this.pending.delete(message.id);
        if (message.error) pending.reject(new Error(`CDP ${message.error.code}: ${message.error.message}`));
        else pending.resolve(message.result ?? {});
        return;
      }
      if (!message.method) return;
      for (const listener of this.listeners.get(message.method) ?? []) listener(message.params ?? {});
    });
  }

  on(method, listener) {
    if (!this.listeners.has(method)) this.listeners.set(method, []);
    this.listeners.get(method).push(listener);
  }

  send(method, params = {}) {
    const id = ++this.sequence;
    return new Promise((resolveCommand, rejectCommand) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        rejectCommand(new Error(`CDP command timed out: ${method}`));
      }, 15_000);
      this.pending.set(id, {
        resolve: (value) => {
          clearTimeout(timer);
          resolveCommand(value);
        },
        reject: (error) => {
          clearTimeout(timer);
          rejectCommand(error);
        },
      });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  async evaluate(expression) {
    const result = await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
      userGesture: true,
    });
    if (result.exceptionDetails) stop(`browser evaluation failed: ${result.exceptionDetails.text}`);
    return result.result?.value;
  }

  close() {
    this.socket.close();
  }
}

export async function runInteraction(client, project) {
  if (project === "admin") {
    const before = await client.evaluate(`document.body.innerText.includes(${JSON.stringify(expectedAdminState)})`);
    if (before) stop("admin staged-state assertion was already true before interaction");
    const interaction = await client.evaluate(`(() => {
      const input = document.querySelector('input[aria-label="Draft a research question"]');
      const button = document.querySelector('button.draft-action');
      if (!input || !button) return { ready: false };
      input.focus();
      input.value = 'Firebat2 interaction proof';
      input.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: 'Firebat2 interaction proof' }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
      button.click();
      return { ready: true, inputValue: input.value, buttonText: button.innerText.trim() };
    })()`);
    if (!interaction?.ready || interaction.inputValue !== "Firebat2 interaction proof" || interaction.buttonText !== "Stage local draft") {
      stop("admin input/click interaction did not execute against the expected controls");
    }
    await waitUntil(
      () => client.evaluate(`document.body.innerText.includes(${JSON.stringify(expectedAdminState)})`),
      "admin reactive staged state",
    );
    return {
      action: "type-draft-and-click-stage-local-draft",
      inputValue: interaction.inputValue,
      assertedState: expectedAdminState,
      publicAdminControlCount: null,
    };
  }

  if (project === "public-site") {
    const result = await client.evaluate(`(() => {
      const body = document.body.innerText;
      const adminControlCount = document.querySelectorAll('input[aria-label="Draft a research question"], .draft-panel, .health-card, button.draft-action').length;
      const hasAdminText = body.includes('Stage local draft') || body.includes('Gateway health') || body.includes('Research work, made navigable.');
      const mathematics = [...document.querySelectorAll('button')].find((button) => button.innerText.trim() === 'Mathematics');
      if (!mathematics) return { ready: false, adminControlCount, hasAdminText };
      mathematics.click();
      return { ready: true, adminControlCount, hasAdminText };
    })()`);
    if (!result?.ready) stop("public Mathematics filter was not available");
    if (result.adminControlCount !== 0 || result.hasAdminText) stop("public site exposed an administrative control or label");
    await waitUntil(
      () => client.evaluate("document.body.innerText.includes('Selected: Mathematics')"),
      "public reactive topic state",
    );
    return {
      action: "click-mathematics-filter",
      assertedState: "Selected: Mathematics",
      publicAdminControlCount: 0,
    };
  }

  stop(`unsupported browser project: ${project}`);
}

async function main() {
  const project = argument("--project");
  const url = new URL(argument("--url"));
  const outputDirectory = resolve(argument("--output-directory"));
  const profileDirectory = resolve(argument("--profile-directory"));
  const chromiumInput = resolve(argument("--chromium"));
  if (!["admin", "public-site"].includes(project)) stop("project must be admin or public-site");
  if (url.protocol !== "http:" || url.hostname !== "127.0.0.1" || !url.port) {
    stop("browser URL must be loopback HTTP with an explicit port");
  }
  for (const [label, path] of [["output", outputDirectory], ["profile", profileDirectory]]) {
    if (!existsSync(path) || !lstatSync(path).isDirectory() || lstatSync(path).isSymbolicLink()) {
      stop(`${label} directory must be an existing real directory`);
    }
    if (realpathSync(path) !== path) stop(`${label} directory must already be canonical`);
  }
  if (!existsSync(chromiumInput)) stop("Chromium path does not exist");
  const chromium = realpathSync(chromiumInput);
  if (!lstatSync(chromium).isFile()) stop("Chromium target is not a regular file");

  const version = spawnSync(chromium, ["--version"], { encoding: "utf8", timeout: 5_000 });
  if (version.status !== 0 || !/^Chromium \d+\./.test(version.stdout.trim())) {
    stop("fixed Chromium returned an unexpected version");
  }

  const chromiumStderr = [];
  const browser = spawn(chromium, [
    "--headless=new",
    "--disable-background-networking",
    "--disable-component-update",
    "--disable-default-apps",
    "--disable-extensions",
    "--disable-gpu",
    "--disable-sync",
    "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1",
    "--metrics-recording-only",
    "--no-first-run",
    "--no-proxy-server",
    "--remote-debugging-address=127.0.0.1",
    "--remote-debugging-port=0",
    "--safebrowsing-disable-auto-update",
    `--user-data-dir=${profileDirectory}`,
    "--window-size=1440,1100",
    "about:blank",
  ], { stdio: ["ignore", "ignore", "pipe"] });
  browser.stderr.setEncoding("utf8");
  browser.stderr.on("data", (chunk) => {
    if (chromiumStderr.join("").length < 128_000) chromiumStderr.push(chunk);
  });

  let client;
  try {
    const portFile = join(profileDirectory, "DevToolsActivePort");
    const debuggingPort = await waitUntil(() => {
      if (browser.exitCode !== null) stop(`Chromium exited before CDP startup: ${chromiumStderr.join("").slice(-4000)}`);
      if (!existsSync(portFile)) return false;
      const firstLine = readFileSync(portFile, "utf8").split(/\r?\n/, 1)[0];
      return /^[1-9][0-9]{3,4}$/.test(firstLine) ? firstLine : false;
    }, "Chromium DevTools port");
    const targets = await (await fetch(`http://127.0.0.1:${debuggingPort}/json/list`)).json();
    const page = targets.find((target) => target.type === "page");
    if (!page?.webSocketDebuggerUrl) stop("Chromium did not expose a page CDP target");
    client = new CdpClient(page.webSocketDebuggerUrl);
    await client.connect();

    const exceptions = [];
    const loadFailures = [];
    const consoleErrors = [];
    const remoteRequests = [];
    const requests = [];
    const pageWebSockets = [];
    const pageWebTransports = [];
    client.on("Runtime.exceptionThrown", (event) => exceptions.push(event.exceptionDetails?.text ?? "exception"));
    client.on("Runtime.consoleAPICalled", (event) => {
      if (event.type === "error" || event.type === "assert") consoleErrors.push(event.type);
    });
    client.on("Network.loadingFailed", (event) => loadFailures.push(event.errorText ?? "load failure"));
    client.on("Network.webSocketCreated", (event) => pageWebSockets.push(event.url ?? "unknown"));
    client.on("Network.webTransportCreated", (event) => pageWebTransports.push(event.url ?? "unknown"));
    client.on("Network.requestWillBeSent", (event) => {
      const requestUrl = event.request?.url ?? "";
      requests.push(requestUrl);
      if (!requestUrl.startsWith(`${url.origin}/`) && !/^(?:data|blob):/.test(requestUrl)) remoteRequests.push(requestUrl);
    });
    await Promise.all([
      client.send("Page.enable"),
      client.send("Runtime.enable"),
      client.send("Network.enable"),
    ]);
    await client.send("Page.navigate", { url: url.href });
    await waitUntil(
      () => client.evaluate("document.readyState === 'complete' && document.body && document.body.innerText.includes('MaCSad')"),
      `${project} application mount`,
    );
    const interaction = await runInteraction(client, project);
    await delay(250);
    if (
      exceptions.length ||
      consoleErrors.length ||
      loadFailures.length ||
      remoteRequests.length ||
      pageWebSockets.length ||
      pageWebTransports.length
    ) {
      stop(
        `browser runtime boundary failed: ${JSON.stringify({
          exceptions,
          consoleErrors,
          loadFailures,
          remoteRequests,
          pageWebSockets,
          pageWebTransports,
        })}`,
      );
    }
    const dom = await client.evaluate("document.documentElement.outerHTML");
    if (typeof dom !== "string" || !dom.includes("<body")) stop("CDP did not return a mounted DOM");
    const screenshot = await client.send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true });
    if (!/^[A-Za-z0-9+/]+=*$/.test(screenshot.data ?? "")) stop("CDP did not return a PNG screenshot");
    writeFileSync(join(outputDirectory, "dom.html"), `${dom}\n`, { mode: 0o600 });
    writeFileSync(join(outputDirectory, "screenshot.png"), Buffer.from(screenshot.data, "base64"), { mode: 0o600 });
    writeFileSync(
      join(outputDirectory, "interaction.json"),
      `${JSON.stringify({ schema: "macsad-browser-interaction/1", project, ...interaction }, null, 2)}\n`,
      { mode: 0o600 },
    );
    writeFileSync(
      join(outputDirectory, "browser.log"),
      [
        `browser: ${version.stdout.trim()}`,
        `loopback requests: ${requests.length}`,
        "observed remote page HTTP(S) requests: 0",
        "observed page WebSockets: 0",
        "observed page WebTransports: 0",
        "runtime exceptions: 0",
        "console errors: 0",
        "load failures: 0",
        "interaction: passed",
        "",
      ].join("\n"),
      { mode: 0o600 },
    );
    await client.send("Browser.close");
  } finally {
    if (client) client.close();
    if (browser.exitCode === null) browser.kill("SIGTERM");
    if (browser.exitCode === null) {
      await Promise.race([
        new Promise((resolveExit) => browser.once("exit", resolveExit)),
        delay(5_000),
      ]);
    }
    if (browser.exitCode === null) {
      browser.kill("SIGKILL");
      await Promise.race([
        new Promise((resolveExit) => browser.once("exit", resolveExit)),
        delay(5_000),
      ]);
    }
    if (browser.exitCode === null) stop("Chromium did not terminate after SIGKILL");
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`error: ${error.message}\n`);
    process.exitCode = 1;
  });
}
