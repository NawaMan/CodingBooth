// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

/**
 * CodingBooth language servers for Fresh.
 *
 * Fresh knows which server each language wants (markdown -> marksman, ...),
 * but starts none by default and can only offer to copy an install URL when
 * one is missing. Inside a booth every server in the lsp template has a setup
 * script, so this plugin closes the loop:
 *
 * - A server that is on PATH auto-starts for its languages, unless the user's
 *   own config.json already says whether it should.
 * - A missing one gets an "Install <server>" row in the LSP-Servers popup
 *   (the status-bar LSP indicator). Picking it runs
 *   `sudo -n lsp--<server>--setup.sh` and starts the server when it lands.
 * - "Booth: Install Language Server" in the palette lists every missing one.
 *
 * A server installed here lasts until the booth is rebuilt; the status line
 * names the lsp+<ext> selection that keeps it.
 */

const editor = getEditor();

/** Namespace for the LSP-Servers popup rows; picks come back as `booth-lsp|<id>`. */
const PLUGIN_ID = "booth-lsp";
const INSTALL_POPUP = "booth-lsp-install";

interface Server {
  /** lsp--<setup>--setup.sh */
  setup: string;
  /** The lsp+<extension> that installs it at build time. */
  extension: string;
  /** Fresh language ids it serves. */
  languages: string[];
  /** Command and args when Fresh has no default for the language. */
  command: string;
  args: string[];
  /** A runtime the setup needs that the base image does not have. */
  needs?: "node" | "python" | "java";
}

const SERVERS: Server[] = [
  { setup: "marksman", extension: "markdown", languages: ["markdown"], command: "marksman", args: ["server"] },
  { setup: "taplo", extension: "toml", languages: ["toml"], command: "taplo", args: ["lsp", "stdio"] },
  { setup: "terraform-ls", extension: "terraform", languages: ["terraform"], command: "terraform-ls", args: ["serve"] },
  { setup: "sqls", extension: "sql", languages: ["sql"], command: "sqls", args: [] },
  { setup: "yaml", extension: "yaml", languages: ["yaml"], command: "yaml-language-server", args: ["--stdio"], needs: "node" },
  { setup: "bash", extension: "bash", languages: ["bash"], command: "bash-language-server", args: ["start"], needs: "node" },
  {
    setup: "vscode-langservers", extension: "json", languages: ["json", "jsonc", "html", "css"],
    command: "vscode-json-language-server", args: ["--stdio"], needs: "node",
  },
  {
    setup: "typescript", extension: "typescript", languages: ["typescript", "javascript"],
    command: "typescript-language-server", args: ["--stdio"], needs: "node",
  },
  { setup: "tailwindcss", extension: "tailwind", languages: ["tailwindcss"], command: "tailwindcss-language-server", args: ["--stdio"], needs: "node" },
  { setup: "dockerfile", extension: "dockerfile", languages: ["dockerfile"], command: "docker-langserver", args: ["--stdio"], needs: "node" },
  { setup: "pylsp", extension: "python", languages: ["python"], command: "pylsp", args: [], needs: "python" },
  { setup: "clangd", extension: "c", languages: ["c", "cpp"], command: "clangd", args: [] },
  { setup: "jdtls", extension: "java", languages: ["java"], command: "jdtls", args: [], needs: "java" },
  { setup: "svelte", extension: "svelte", languages: ["svelte"], command: "svelteserver", args: ["--stdio"], needs: "node" },
];

/** File names of open buffers that belong to a language, so an install can start its server. */
const LANGUAGE_FILES: Record<string, RegExp> = {
  markdown: /\.(md|markdown)$/i,
  toml: /\.toml$/i,
  terraform: /\.(tf|tfvars)$/i,
  sql: /\.sql$/i,
  yaml: /\.ya?ml$/i,
  bash: /\.(sh|bash)$/i,
  json: /\.json$/i,
  jsonc: /\.jsonc$/i,
  html: /\.html?$/i,
  css: /\.css$/i,
  typescript: /\.(ts|tsx|mts|cts)$/i,
  javascript: /\.(js|jsx|mjs|cjs)$/i,
  dockerfile: /(^|\/)(Dockerfile|Containerfile)[^/]*$|\.dockerfile$/i,
  python: /\.pyi?$/i,
  c: /\.[ch]$/i,
  cpp: /\.(cc|cpp|cxx|c\+\+|hh|hpp|hxx)$/i,
  java: /\.java$/i,
  svelte: /\.svelte$/i,
};

let installing: string | null = null;

/** Fresh resolves the command for a language from its defaults plus the user's config. */
function commandFor(server: Server, language: string): string {
  const lsp = (editor.getConfig() as any)?.lsp ?? {};
  const entries = lsp[language];
  const first = Array.isArray(entries) ? entries[0] : entries;
  return (first && first.command) || server.command;
}

function onPath(command: string): boolean {
  if (command.includes("/")) return editor.fileExists(command);
  const path = editor.getEnv("PATH") ?? "";
  return path.split(":").some((dir) => dir !== "" && editor.fileExists(editor.pathJoin(dir, command)));
}

function installed(server: Server): boolean {
  return onPath(commandFor(server, server.languages[0]));
}

function runtimeMissing(server: Server): string | null {
  if (server.needs === "node" && !onPath("npm")) return "Node.js (select the nodejs template)";
  if (server.needs === "python" && !editor.fileExists("/opt/python/bin/pip")) return "Python (select the python template)";
  if (server.needs === "java" && !onPath("java")) return "Java 21+ (select the java template)";
  return null;
}

/** True when the user's own config.json decides auto_start for this language. */
function userDecidesAutoStart(language: string): boolean {
  const entries = (editor.getUserConfig() as any)?.lsp?.[language];
  if (entries === undefined || entries === null) return false;
  const list = Array.isArray(entries) ? entries : [entries];
  return list.some((entry: any) => entry && Object.prototype.hasOwnProperty.call(entry, "auto_start"));
}

/**
 * Turn auto_start on for this session. A partial `lsp.<lang>.auto_start` write
 * would reset the entry's other fields, so the whole resolved entry is written
 * back with the one field changed.
 */
function enableAutoStart(server: Server, language: string): void {
  if (userDecidesAutoStart(language)) return;
  const lsp = (editor.getConfig() as any)?.lsp ?? {};
  const current = lsp[language];
  const entries = Array.isArray(current) && current.length > 0
    ? current.map((entry: any) => ({ ...entry, auto_start: true }))
    : [{ command: server.command, args: server.args, enabled: true, auto_start: true }];
  editor.setSetting(`lsp.${language}`, entries);
}

function hasOpenBuffer(language: string): boolean {
  const pattern = LANGUAGE_FILES[language];
  if (!pattern) return false;
  return editor.listBuffers().some((buffer) => !!buffer.path && pattern.test(buffer.path));
}

/** Install rows in the LSP-Servers popup for a server that is not on PATH; none once it is. */
function publishRows(server: Server): void {
  const missing = installed(server) ? null : runtimeMissing(server);
  for (const language of server.languages) {
    if (installed(server)) {
      editor.setLspMenuContributions(PLUGIN_ID, language, []);
    } else if (missing) {
      editor.setLspMenuContributions(PLUGIN_ID, language, [
        { id: `needs:${server.setup}`, label: `Install ${server.command}: needs ${missing}` },
      ]);
    } else {
      editor.setLspMenuContributions(PLUGIN_ID, language, [
        { id: `install:${server.setup}`, label: `Install ${server.command} (booth)` },
      ]);
    }
  }
}

function lastLine(text: string): string {
  const lines = text.split("\n").map((line) => line.trim()).filter((line) => line !== "");
  return lines.length > 0 ? lines[lines.length - 1] : "";
}

async function install(server: Server): Promise<void> {
  if (installing !== null) {
    editor.setStatus(`Already installing ${installing}; wait for it to finish.`);
    return;
  }
  const missing = runtimeMissing(server);
  if (missing) {
    editor.setStatus(`${server.command} needs ${missing}, then rebuild the booth.`);
    return;
  }
  installing = server.command;
  const script = `lsp--${server.setup}--setup.sh`;
  editor.setStatus(`Installing ${server.command} (sudo ${script}) ...`);
  try {
    const result = await editor.spawnProcess("sudo", ["-n", script]);
    const logDir = editor.pathJoin(editor.getEnv("HOME") ?? "/tmp", ".cache", "booth-lsp");
    const log = editor.pathJoin(logDir, `${server.setup}.log`);
    await editor.spawnProcess("mkdir", ["-p", logDir]);
    editor.writeFile(log, `$ sudo -n ${script}\n\n${result.stdout}\n${result.stderr}\nexit ${result.exit_code}\n`);

    if (result.exit_code !== 0 || !installed(server)) {
      const why = lastLine(result.stderr) || lastLine(result.stdout) || `exit ${result.exit_code}`;
      editor.setStatus(`Installing ${server.command} failed: ${why}`);
      editor.openFile(log);
      return;
    }

    for (const language of server.languages) {
      enableAutoStart(server, language);
    }
    // Let the settings land before the restart reads them.
    await editor.delay(200);
    for (const language of server.languages) {
      if (hasOpenBuffer(language)) editor.restartLspForLanguage(language);
    }
    publishRows(server);
    editor.setStatus(
      `${server.command} installed. It lasts until the booth is rebuilt; select lsp+${server.extension} to keep it.`
    );
  } catch (e) {
    editor.setStatus(`Installing ${server.command} failed: ${e}`);
  } finally {
    installing = null;
  }
}

function serverBySetup(setup: string): Server | undefined {
  return SERVERS.find((server) => server.setup === setup);
}

function start(): void {
  for (const server of SERVERS) {
    if (installed(server)) {
      for (const language of server.languages) {
        enableAutoStart(server, language);
      }
    }
    publishRows(server);
  }
}

// The buffer Fresh opened at launch decided auto_start before this plugin ran,
// so start the installed servers that already have a file waiting.
async function startOpenBuffers(): Promise<void> {
  await editor.delay(300);
  for (const server of SERVERS) {
    if (!installed(server)) continue;
    for (const language of server.languages) {
      if (!userDecidesAutoStart(language) && hasOpenBuffer(language)) {
        editor.restartLspForLanguage(language);
      }
    }
  }
}

editor.on("action_popup_result", (data) => {
  let id: string | null = null;
  if (data.popup_id === "lsp_status" && data.action_id.startsWith(`${PLUGIN_ID}|`)) {
    id = data.action_id.slice(PLUGIN_ID.length + 1);
  } else if (data.popup_id === INSTALL_POPUP) {
    id = data.action_id;
  }
  if (id === null) return;

  const [kind, setup] = id.split(":");
  const server = setup ? serverBySetup(setup) : undefined;
  if (!server) return;
  if (kind === "install") {
    install(server).catch((e) => editor.setStatus(`Installing ${server.command} failed: ${e}`));
  } else if (kind === "needs") {
    editor.setStatus(`${server.command} needs ${runtimeMissing(server) ?? "its runtime"}, then rebuild the booth.`);
  }
});

registerHandler("booth_lsp_install_menu", function () {
  const missing = SERVERS.filter((server) => !installed(server));
  if (missing.length === 0) {
    editor.setStatus("Every booth language server is already installed.");
    return;
  }
  editor.showActionPopup({
    id: INSTALL_POPUP,
    title: "Install Language Server",
    message: "Runs the booth setup script with sudo. It lasts until the booth is rebuilt.",
    actions: [
      ...missing.map((server) => {
        const needs = runtimeMissing(server);
        return needs
          ? { id: `needs:${server.setup}`, label: `${server.command} (${server.languages.join(", ")}): needs ${needs}` }
          : { id: `install:${server.setup}`, label: `${server.command} (${server.languages.join(", ")})` };
      }),
      { id: "dismiss", label: "Dismiss (ESC)" },
    ],
  });
});

editor.registerCommand(
  "Booth: Install Language Server",
  "Install a language server with the booth's lsp--<name>--setup.sh",
  "booth_lsp_install_menu",
  null
);

start();
startOpenBuffers().catch((e) => editor.debug(`booth-lsp: ${e}`));
editor.debug(`booth-lsp: loaded (${SERVERS.length} servers)`);
