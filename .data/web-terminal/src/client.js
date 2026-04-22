import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebglAddon } from "@xterm/addon-webgl";
import { ClipboardAddon } from "@xterm/addon-clipboard";
import { Unicode11Addon } from "@xterm/addon-unicode11";

const RETRY_MS = 200;
const RESIZE_DEBOUNCE_MS = 100;

let terminal, fitAddon, ws, config, overlay, overlayTimer, resizeTimer;

async function loadConfig() {
    while (true) {
        try {
            const res = await fetch("/config");
            if (res.ok) return await res.json();
        } catch (_) {}
        await new Promise((r) => setTimeout(r, RETRY_MS));
    }
}

async function waitForServer() {
    while (true) {
        try {
            const res = await fetch("/health");
            if (res.ok) return;
        } catch (_) {}
        await new Promise((r) => setTimeout(r, RETRY_MS));
    }
}

function showOverlay(text, timeout) {
    if (!overlay) {
        overlay = document.createElement("div");
        overlay.id = "reconnect-overlay";
        document.body.appendChild(overlay);
    }
    overlay.textContent = text;
    overlay.style.color = config?.overlayColor || "#aaa";
    overlay.style.background = config?.overlayBg || "rgba(0, 0, 0, 0.7)";
    overlay.style.display = "flex";
    overlay.style.opacity = "1";

    clearTimeout(overlayTimer);
    if (timeout) {
        overlayTimer = setTimeout(() => {
            overlay.style.opacity = "0";
            setTimeout(() => { overlay.style.display = "none"; }, 200);
        }, timeout);
    }
}

function hideOverlay() {
    clearTimeout(overlayTimer);
    if (overlay) overlay.style.display = "none";
}

function doFit() {
    if (!fitAddon || !terminal) return;
    try { fitAddon.fit(); } catch (_) {}
}

function sendResize() {
    if (ws && ws.readyState === WebSocket.OPEN && terminal) {
        ws.send(JSON.stringify({ type: "resize", cols: terminal.cols, rows: terminal.rows }));
    }
}

function sendInput(data) {
    if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: "input", data }));
    }
}

function connect() {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    ws = new WebSocket(`${proto}//${location.host}/ws`);

    ws.onopen = () => {
        hideOverlay();
        doFit();
        sendResize();
        terminal.focus();
    };

    ws.onmessage = (e) => terminal.write(e.data);

    ws.onclose = async () => {
        showOverlay(config.msgReconnecting);
        await waitForServer();
        location.reload();
    };

    ws.onerror = () => {
        try { ws.close(); } catch (_) {}
    };
}

async function init() {
    config = await loadConfig();
    document.title = config.title;

    showOverlay(config.msgConnecting);

    const container = document.getElementById("terminal");
    container.style.width = window.innerWidth + "px";
    container.style.height = window.innerHeight + "px";

    await document.fonts.ready;

    terminal = new Terminal({
        fontFamily: config.fontFamily,
        fontSize: config.fontSize,
        fontWeight: config.fontWeight,
        fontWeightBold: config.fontWeightBold,
        scrollback: config.scrollback ?? 50000,
        theme: config.theme,
        allowProposedApi: true,
    });

    fitAddon = new FitAddon();
    terminal.loadAddon(fitAddon);
    terminal.open(container);

    try { terminal.loadAddon(new WebglAddon()); } catch (_) {}
    try { terminal.loadAddon(new ClipboardAddon()); } catch (_) {}
    try { terminal.loadAddon(new Unicode11Addon()); terminal.unicode.activeVersion = "11"; } catch (_) {}

    terminal.onData(sendInput);
    terminal.onResize(() => sendResize());

    terminal.onSelectionChange(() => {
        const sel = terminal.getSelection();
        if (!sel) return;
        const write = navigator.clipboard && navigator.clipboard.writeText
            ? navigator.clipboard.writeText(sel)
            : new Promise((_, reject) => reject());
        write
            .then(() => { terminal.clearSelection(); showOverlay(config.msgCopied, 400); })
            .catch(() => {});
    });

    doFit();

    window.addEventListener("resize", () => {
        container.style.width = window.innerWidth + "px";
        container.style.height = window.innerHeight + "px";
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(() => {
            doFit();
            sendResize();
        }, RESIZE_DEBOUNCE_MS);
    });

    connect();
}

init();
