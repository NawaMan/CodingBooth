# vnc_lite.html Password Plaintext Fix

> The noVNC `vnc_lite.html` page uses `prompt()` for VNC password entry, which displays the password in plaintext. This documents the problem and the patch to fix it.

Back to [README](../README.md)

---

## Table of Contents

- [Background](#background)
- [The Problem](#the-problem)
- [The Fix](#the-fix)
- [Where to Apply](#where-to-apply)
- [Why vnc_lite.html Instead of vnc.html](#why-vnc_litehtml-instead-of-vnchtml)

---

## Background

Desktop variants (xfce, kde, lxqt) serve a browser-based VNC session via noVNC. When `--public` is used, VNC authentication is enabled — the user must enter the password to access the desktop.

noVNC ships two client pages:

| Page | UI | Password Input |
|------|-----|----------------|
| `vnc.html` | Full UI with sidebar, settings, clipboard | `<input type="password">` — masked |
| `vnc_lite.html` | Minimal, self-contained, no external CSS | `prompt()` — **plaintext** |

CodingBooth uses `vnc_lite.html` because `vnc.html` has issues when deployed behind cloud proxies/load balancers.

---

## The Problem

In `/usr/share/novnc/vnc_lite.html`, the credential handler is:

```js
function credentialsAreRequired(e) {
    const password = prompt("Password Required:");
    rfb.sendCredentials({ password: password });
}
```

The browser `prompt()` function always shows input as plaintext — there is no masked variant. This means the VNC password is visible on screen when entered.

---

## The Fix

Replace the `prompt()` call with a custom modal dialog using `<input type="password">`.

### 1. Add a password dialog to the `<body>`

Insert before `<div id="top_bar">`:

```html
<div id="password_dlg" style="display:none; position:fixed; inset:0; background:rgba(0,0,0,.5); align-items:center; justify-content:center; z-index:1000;">
  <form id="password_form" style="background:#fff; padding:1.5rem; border-radius:8px; min-width:260px;">
    <label for="password_input" style="display:block; margin-bottom:.5rem; font:bold 14px Helvetica,sans-serif;">Password Required:</label>
    <input id="password_input" type="password" style="width:100%; padding:.4rem; box-sizing:border-box;">
    <button type="submit" style="margin-top:.75rem; padding:.4rem .8rem;">Submit</button>
  </form>
</div>
```

### 2. Replace the `credentialsAreRequired` function

```js
function credentialsAreRequired(e) {
    const dlg   = document.getElementById('password_dlg');
    const form  = document.getElementById('password_form');
    const input = document.getElementById('password_input');
    dlg.style.display = 'flex';
    input.value = '';
    input.focus();
    form.onsubmit = function(ev) {
        ev.preventDefault();
        dlg.style.display = 'none';
        rfb.sendCredentials({ password: input.value });
    };
}
```

No other changes to `vnc_lite.html` are needed.

---

## Where to Apply

`vnc_lite.html` comes from the Ubuntu `novnc` package and is installed at `/usr/share/novnc/vnc_lite.html`. The patch must be applied at image build time in the desktop setup scripts, using `sed` or a heredoc override — similar to how `index.html` is already replaced in these files:

| Setup Script | Location |
|-------------|----------|
| `variants/base/setups/xfce--setup.sh` | XFCE variant |
| `variants/base/setups/kde--setup.sh` | KDE variant |
| `variants/base/setups/lxqt--setup.sh` | LXQt variant |

Each of these scripts already patches `/usr/share/novnc/index.html` with a custom landing page (autoconnect redirect). The `vnc_lite.html` patch should be applied in the same section.

---

## Why vnc_lite.html Instead of vnc.html

`vnc.html` uses the full noVNC UI which loads external CSS and JS modules (`app/ui.js`, `app/styles/base.css`, etc.). This full UI has known issues when deployed behind cloud reverse proxies and load balancers — resource loading failures, WebSocket path mismatches, and caching problems.

`vnc_lite.html` is self-contained (inline CSS, single `<script type="module">` block) which makes it reliable in cloud deployments. The tradeoff is a minimal UI — and the plaintext password bug documented here.
