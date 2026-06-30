import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebglAddon } from "@xterm/addon-webgl";
import { ClipboardAddon } from "@xterm/addon-clipboard";
import { Unicode11Addon } from "@xterm/addon-unicode11";

const RETRY_MS = 200;
const RESIZE_DEBOUNCE_MS = 100;
const CLIPBOARD_FLUSH_DELAYS_MS = [0, 30, 80, 180, 350];
const CLIPBOARD_GESTURE_MS = 2500;
const OSC52_RE = /\x1b\]52;[^;]*;([A-Za-z0-9+/=]+)(?:\x07|\x1b\\)/g;

// Nerd Font Mono / Propo variants mis-render in xterm.js; keep plain "* Nerd Font" / "* NF".
const NERD_FONT_CANDIDATES = [
    "JetBrainsMono Nerd Font",
    "FiraCode Nerd Font",
    "Hack Nerd Font",
    "0xProto Nerd Font",
    "CaskaydiaCove Nerd Font",
    "MesloLGS Nerd Font",
    "MesloLGS NF",
    "UbuntuMono Nerd Font",
    "DejaVuSansMono Nerd Font",
    "SourceCodePro Nerd Font",
    "VictorMono Nerd Font",
    "Monoid Nerd Font",
    "GeistMono Nerd Font",
    "Iosevka Nerd Font",
    "ComicShannsMono Nerd Font",
];

function isAllowedSystemFont(family) {
    const name = family.trim();
    if (name === "monospace") return true;
    if (/ mono$/i.test(name) || / mono /i.test(name)) return false;
    return true;
}

function isAllowedNerdFontFamily(family) {
    const name = family.trim();
    if (!name.includes("Nerd Font") && !name.endsWith(" NF")) return false;
    if (name === "Nerd Font" || name === "Nerd Font Mono" || name === "Nerd Font Propo") return false;
    if (name.includes(" Nerd Font Mono") || name.includes(" Nerd Font Propo")) return false;
    return name.endsWith(" Nerd Font") || name.endsWith(" NF");
}

function parseFontFamilyList(fontFamily) {
    const parts = [];
    const re = /"([^"]+)"|'([^']+)'|([^,]+)/g;
    let match;
    while ((match = re.exec(fontFamily)) !== null) {
        parts.push((match[1] || match[2] || match[3]).trim());
    }
    return parts.filter(Boolean);
}

async function fontIsAvailable(family, size) {
    const spec = `${size}px "${family}"`;
    try {
        await document.fonts.load(spec);
        return document.fonts.check(spec);
    } catch (_) {
        return false;
    }
}

async function discoverLocalNerdFonts() {
    if (!window.queryLocalFonts) return [];
    try {
        const fonts = await window.queryLocalFonts();
        return [...new Set(fonts.map((font) => font.family))].filter(isAllowedNerdFontFamily);
    } catch (_) {
        return [];
    }
}

async function resolveFontFamily(fontFamily, fontSize) {
    const parts = parseFontFamilyList(fontFamily);
    const fallbacks = parts.filter(
        (part) => !part.includes("Nerd Font") && !part.endsWith(" NF") && isAllowedSystemFont(part),
    );
    const fromConfig = parts.filter(isAllowedNerdFontFamily);
    const discovered = await discoverLocalNerdFonts();
    const candidates = [...new Set([...fromConfig, ...NERD_FONT_CANDIDATES, ...discovered])];

    const available = [];
    for (const family of candidates) {
        if (await fontIsAvailable(family, fontSize)) available.push(family);
    }

    const stack = [...available, ...fallbacks];
    return stack.map((family) => (family.includes(" ") ? `"${family}"` : family)).join(", ");
}

let terminal, fitAddon, ws, config, overlay, overlayTimer, resizeTimer, pendingClipboard, clipboardGestureUntil = 0;

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

function decodeOsc52Base64(b64) {
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder().decode(bytes);
}

function scanForOsc52(data) {
    OSC52_RE.lastIndex = 0;
    let match;
    while ((match = OSC52_RE.exec(data)) !== null) {
        try {
            handleTmuxCopy(decodeOsc52Base64(match[1]));
        } catch (_) {}
    }
}

function handleTmuxCopy(text) {
    if (!text) return;
    pendingClipboard = text;
    if (Date.now() < clipboardGestureUntil) {
        copyToClipboard(text);
    }
}

function copyWithCopyEvent(text) {
    let copied = false;
    const onCopy = (event) => {
        event.clipboardData.setData("text/plain", text);
        event.preventDefault();
        copied = true;
    };
    document.addEventListener("copy", onCopy, { once: true, capture: true });
    const ok = document.execCommand("copy");
    document.removeEventListener("copy", onCopy, { capture: true });
    return ok && copied;
}

function fallbackCopy(text) {
    try {
        return copyWithCopyEvent(text);
    } catch (_) {
        return false;
    }
}

function copyToClipboard(text) {
    if (!text) return Promise.resolve(false);

    const onSuccess = () => {
        pendingClipboard = null;
        showOverlay(config.msgCopied, 400);
        return true;
    };
    const onFailure = () => {
        pendingClipboard = text;
        showOverlay(config.msgCopyFailed || "Copy blocked — click terminal and press Cmd+C", 1500);
        return false;
    };

    if (copyWithCopyEvent(text)) {
        return Promise.resolve(onSuccess());
    }

    if (navigator.clipboard?.writeText) {
        return navigator.clipboard.writeText(text).then(onSuccess).catch(() => {
            if (fallbackCopy(text)) return onSuccess();
            return onFailure();
        });
    }

    if (fallbackCopy(text)) return Promise.resolve(onSuccess());
    return Promise.resolve(onFailure());
}

function flushPendingClipboard() {
    if (pendingClipboard) copyToClipboard(pendingClipboard);
}

function scheduleClipboardFlush() {
    for (const delay of CLIPBOARD_FLUSH_DELAYS_MS) {
        setTimeout(flushPendingClipboard, delay);
    }
}

function noteClipboardGesture() {
    clipboardGestureUntil = Date.now() + CLIPBOARD_GESTURE_MS;
}

function setupTmuxClipboard() {
    terminal.element.addEventListener("mousedown", noteClipboardGesture);
    terminal.element.addEventListener("mouseup", () => {
        noteClipboardGesture();
        scheduleClipboardFlush();
    });
    terminal.element.addEventListener("contextmenu", (event) => event.preventDefault());
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

    ws.onmessage = (event) => {
        const data = event.data;
        if (typeof data === "string") scanForOsc52(data);
        terminal.write(data);
    };

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

    const fontFamily = await resolveFontFamily(config.fontFamily, config.fontSize);

    terminal = new Terminal({
        fontFamily,
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

    setupTmuxClipboard();
    try { terminal.loadAddon(new ClipboardAddon()); } catch (_) {}
    try { terminal.loadAddon(new Unicode11Addon()); terminal.unicode.activeVersion = "11"; } catch (_) {}
    if (!/Mac|iPhone|iPad/i.test(navigator.userAgent)) {
        try { terminal.loadAddon(new WebglAddon()); } catch (_) {}
    }

    terminal.onData(sendInput);
    terminal.onResize(() => sendResize());

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
