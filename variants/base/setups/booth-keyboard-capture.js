// Booth keyboard capture — shared "Full screen" control for browser UIs.
//
// A booth's browser UI runs in an ordinary tab, so shortcuts the browser
// reserves for itself (Ctrl+W, Ctrl+T, Ctrl+Tab, Ctrl+N, ...) never reach the
// terminal or remote desktop underneath — no page-level preventDefault() can
// stop that; the browser acts on them before the page's own handlers run.
//
// The Keyboard Lock API (navigator.keyboard.lock()) can take those combos
// back, but only for a page that is both fullscreen and running in a
// Chromium-based browser — there is no cross-browser equivalent, so this
// module always feature-detects rather than assuming support.
//
// window.BoothKeyboardCapture.toggle() requests fullscreen + keyboard lock, or
// releases both if already engaged. isSupported() lets a caller hide or
// disable its own button rather than offering a control that can only
// half-work in the current browser.
(function () {
  "use strict";

  function supported() {
    return !!(navigator.keyboard && typeof navigator.keyboard.lock === "function");
  }

  // Only the keys browser shortcuts are built from. lock() with no list takes
  // every key, which also kept PrintScreen and the media/volume keys from ever
  // reaching the host. Every entry must be a KeyboardEvent.code Chrome knows —
  // one unknown name and lock() rejects the whole call.
  var LOCKED_KEYS = (function () {
    var keys = [];
    var i;
    for (i = 0; i < 26; i++) {
      keys.push("Key" + String.fromCharCode(65 + i));
    }
    for (i = 0; i < 10; i++) {
      keys.push("Digit" + i, "Numpad" + i);
    }
    for (i = 1; i <= 12; i++) {
      keys.push("F" + i);
    }
    return keys.concat([
      "Backquote", "Minus", "Equal", "BracketLeft", "BracketRight", "Backslash",
      "Semicolon", "Quote", "Comma", "Period", "Slash",
      "IntlBackslash", "IntlRo", "IntlYen",
      "Space", "Tab", "Enter", "Backspace", "Escape", "ContextMenu",
      "Insert", "Delete", "Home", "End", "PageUp", "PageDown",
      "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight",
      "NumpadAdd", "NumpadSubtract", "NumpadMultiply", "NumpadDivide",
      "NumpadDecimal", "NumpadEnter",
      "ShiftLeft", "ShiftRight", "ControlLeft", "ControlRight",
      "AltLeft", "AltRight", "MetaLeft", "MetaRight"
    ]);
  })();

  var active = false;
  var listeners = [];

  function notify() {
    listeners.forEach(function (callback) {
      try {
        callback(active);
      } catch (error) {
        if (window.console) {
          window.console.error("booth-keyboard-capture: listener failed", error);
        }
      }
    });
  }

  function unlockKeyboard() {
    try {
      navigator.keyboard.unlock();
    } catch (error) {
      // unlock() throws if never locked, or if the browser dropped the lock
      // itself (e.g. the user exited fullscreen with Esc) — either way there
      // is nothing left to release.
    }
  }

  function exitFullscreenIfAny() {
    if (document.fullscreenElement) {
      try {
        document.exitFullscreen();
      } catch (error) {
        // Nothing more to do if the browser refuses; the page stays fullscreen
        // and the user can exit with Esc as usual.
      }
    }
  }

  function release() {
    if (!active) {
      return;
    }
    active = false;
    unlockKeyboard();
    notify();
  }

  // The user can always leave fullscreen with Esc regardless of the lock —
  // that must drop `active` too, or the button would claim capture is still
  // on when the browser has already ended it.
  document.addEventListener("fullscreenchange", function () {
    if (!document.fullscreenElement) {
      release();
    }
  });

  function engage() {
    if (!supported()) {
      return Promise.resolve(false);
    }
    var target = document.documentElement;
    if (!target.requestFullscreen) {
      return Promise.resolve(false);
    }
    return target.requestFullscreen()
      .then(function () {
        return navigator.keyboard.lock(LOCKED_KEYS);
      })
      .then(function () {
        active = true;
        notify();
        return true;
      })
      .catch(function (error) {
        if (window.console) {
          window.console.error("booth-keyboard-capture: could not engage", error);
        }
        // Fullscreen without the lock buys nothing — don't leave the tab
        // stuck fullscreen for no gain.
        exitFullscreenIfAny();
        return false;
      });
  }

  window.BoothKeyboardCapture = {
    isSupported: supported,
    isActive: function () {
      return active;
    },
    onChange: function (callback) {
      listeners.push(callback);
    },
    toggle: function () {
      if (active) {
        release();
        exitFullscreenIfAny();
        return Promise.resolve(false);
      }
      return engage();
    }
  };
})();
