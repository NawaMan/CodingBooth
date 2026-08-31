// Booth readiness gate — shared by every variant's browser UI.
//
// Every variant is fronted by nginx, and nginx binds the booth's port before
// the service behind it is listening. A page that points its frames at that
// service the moment the port answers gets nginx's raw 502 instead: the split
// UI in all four panes, the wrapper variants in their one full-screen frame.
//
// This polls /__booth/health — which proxies to that service, so it only
// answers 200 once there is something to show — and lets a page hold its frames
// back until then. It keeps polling afterwards, because startup is not the only
// gap: `booth--restart` restarts the service under a tab that is already open,
// and a service that dies mid-session leaves the same 502 behind.
//
// Pages use it as:
//
//     BoothReady.onUp(function () { iframe.src = wherever; });
//
// onUp fires on every transition to serving, the first one included — so the
// same handler does the initial load and every reload after a restart.
//
// It has a second job. A booth is reached by port, and ports get reused: stop
// one booth, start another on the same port, and the browser hands the URL to a
// tab that is already open — which still shows the first booth's page, now
// driving a booth that never served it. Nothing on that page is right, and the
// frames are the visible half: a terminal UI's panes ask a notebook booth for
// /s1/ and get Jupyter's 404. So every probe also checks *which* booth answered,
// and reloads the page outright when it is not the one that served it.
(function () {
  "use strict";

  var HEALTH_URL = "/__booth/health";

  // The header the booth stamps its identity into, and the shape it must have.
  // Anything else — an image too old to send it, a template that failed to
  // substitute — leaves the check switched off rather than reloading blindly.
  var INSTANCE_HEADER = "X-Booth-Instance";
  var INSTANCE_PATTERN = /^[0-9a-f]{16,}$/;
  var RELOADED_FOR_KEY = "cb.booth.reloadedFor";

  // While there is nothing to show, poll often: this delay is what the user
  // waits through once the booth is actually ready. Once it is serving, poll
  // rarely — that is only watching for it to go away.
  var POLL_WAITING_MS = 500;
  var POLL_SERVING_MS = 5000;
  var PROBE_TIMEOUT_MS = 4000;

  // A booth that answers straight away never shows a splash, and one that comes
  // up a moment later should not flash a panel on the way past. Every wait —
  // the first one and every reconnect — gets this much grace before the splash
  // is allowed on screen.
  var SPLASH_DELAY_MS = 600;

  var serving = false;
  var everServed = false;
  var upCallbacks = [];
  var splash = null;
  var splashMessage = null;
  var splashAllowedAt = Date.now() + SPLASH_DELAY_MS;
  var waitingForBody = false;

  function buildSplash() {
    var host = document.createElement("div");
    host.id = "booth-ready-splash";
    host.setAttribute("role", "status");
    host.setAttribute("aria-live", "polite");
    // Below the message overlay (10000) so a booth message still reads over it.
    host.style.cssText = [
      "position:fixed", "inset:0", "z-index:9000",
      "display:flex", "flex-direction:column",
      "align-items:center", "justify-content:center", "gap:14px",
      "background:#0b1018", "color:#e7edf5",
      "font-family:'IBM Plex Sans','Segoe UI',sans-serif", "font-size:14px"
    ].join(";");

    var style = document.createElement("style");
    style.textContent = "@keyframes booth-ready-spin{to{transform:rotate(360deg)}}";

    var spinner = document.createElement("div");
    spinner.style.cssText = [
      "width:26px", "height:26px", "border-radius:50%",
      "border:3px solid rgba(231,237,245,0.18)", "border-top-color:#2f8dff",
      "animation:booth-ready-spin 0.9s linear infinite"
    ].join(";");

    splashMessage = document.createElement("div");

    host.appendChild(style);
    host.appendChild(spinner);
    host.appendChild(splashMessage);
    return host;
  }

  // The gate runs from <head> so it is watching before the page's own frames
  // are parsed, which means the first probes can resolve before there is a body
  // to hang the splash on.
  function showSplash(message) {
    if (Date.now() < splashAllowedAt) {
      return;
    }
    if (!document.body) {
      if (!waitingForBody) {
        waitingForBody = true;
        document.addEventListener("DOMContentLoaded", function () {
          waitingForBody = false;
          if (!serving) {
            showSplash(message);
          }
        }, { once: true });
      }
      return;
    }
    if (!splash) {
      splash = buildSplash();
    }
    splashMessage.textContent = message;
    if (!splash.parentNode) {
      document.body.appendChild(splash);
    }
  }

  function hideSplash() {
    if (splash && splash.parentNode) {
      splash.parentNode.removeChild(splash);
    }
  }

  // One probe of the booth's own health endpoint. The endpoint normalizes every
  // non-5xx status it gets from the service behind nginx to 200, so an ok
  // response is a straight "nginx reached it".
  function probe() {
    var controller = null;
    var abortTimer = null;
    if (typeof AbortController === "function") {
      controller = new AbortController();
      abortTimer = setTimeout(function () { controller.abort(); }, PROBE_TIMEOUT_MS);
    }

    var options = { cache: "no-store", credentials: "same-origin" };
    if (controller) {
      options.signal = controller.signal;
    }

    return fetch(HEALTH_URL, options)
      // The identity is read even from a 502: a booth that has been swapped out
      // is worth catching before the new one has finished starting.
      .then(function (response) {
        return { ok: response.ok, instance: response.headers.get(INSTANCE_HEADER) || "" };
      })
      .catch(function () { return { ok: false, instance: "" }; })
      .then(function (result) {
        if (abortTimer) {
          clearTimeout(abortTimer);
        }
        return result;
      });
  }

  // isStranger reports whether the booth that just answered is a different one
  // from the booth that served this page.
  //
  // Both ids must be well-formed for this to say yes. That is what keeps a
  // missing header or an unsubstituted template from reading as "always a
  // stranger", which would reload the page on a loop.
  function isStranger(instance) {
    var own = window.BOOTH_INSTANCE_ID || "";
    if (!INSTANCE_PATTERN.test(own) || !INSTANCE_PATTERN.test(instance)) {
      return false;
    }
    return instance !== own;
  }

  // reloadForStranger replaces this page with the current booth's own.
  //
  // It goes to the booth's root rather than reloading in place. The path in the
  // bar belongs to the booth that is gone — /booth on a tab left over from a
  // wrapped variant, /lab/tree/… on one left over from a notebook — and the new
  // booth would serve whatever it happens to route that to. The root is the one
  // address every variant answers for itself, and it is what `booth run` opens.
  //
  // Guarded so it can happen at most once per booth: if the reloaded page comes
  // back still claiming a different id, something upstream is wrong and looping
  // on it would only make that harder to see.
  function reloadForStranger(instance) {
    try {
      if (window.sessionStorage.getItem(RELOADED_FOR_KEY) === instance) {
        if (window.console) {
          window.console.error(
            "booth-ready: this page is from another booth, and reloading did not replace it"
          );
        }
        return;
      }
      window.sessionStorage.setItem(RELOADED_FOR_KEY, instance);
    } catch (error) {
      // No sessionStorage (private mode, restricted env). The id check above is
      // strict enough to make one reload the right move anyway.
    }
    // replace, not assign: the dead booth's page is not somewhere Back should
    // return to.
    window.location.replace(window.location.origin + "/");
  }

  function notifyUp() {
    upCallbacks.forEach(function (callback) {
      try {
        callback();
      } catch (error) {
        // One page's handler failing must not stop the others, or the next poll.
        if (window.console) {
          window.console.error("booth-ready: onUp handler failed", error);
        }
      }
    });
  }

  function record(nowServing) {
    if (nowServing === serving) {
      return;
    }
    serving = nowServing;

    if (serving) {
      everServed = true;
      hideSplash();
      notifyUp();
      // Whatever wait comes next — a restart, a crash — starts its own grace
      // period rather than inheriting this one.
      splashAllowedAt = Date.now() + SPLASH_DELAY_MS;
    }
  }

  function poll() {
    probe().then(function (result) {
      if (isStranger(result.instance)) {
        // Nothing else matters — this page does not belong to the booth on this
        // port any more, and loading its frames would only fill them with
        // another booth's answers.
        reloadForStranger(result.instance);
        return;
      }

      record(result.ok);
      if (!serving) {
        // Before the booth has ever answered this is startup; after it has, the
        // booth went away — a restart, or a service that died.
        showSplash(everServed ? "Reconnecting to the booth ..." : "Starting the booth ...");
      }
      setTimeout(poll, serving ? POLL_SERVING_MS : POLL_WAITING_MS);
    });
  }

  window.BoothReady = {
    // isUp reports the last known state, for callers deciding whether to point
    // a frame somewhere right now.
    isUp: function () {
      return serving;
    },

    // onUp registers a handler run on every transition to serving, including
    // the first. A handler registered once the booth is already up runs at
    // once, so registration order does not matter.
    onUp: function (callback) {
      upCallbacks.push(callback);
      if (serving) {
        callback();
      }
    }
  };

  poll();
})();
