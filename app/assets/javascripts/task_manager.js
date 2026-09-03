/* ===========================================================================
   Task Manager — the module's whole client side.
   ---------------------------------------------------------------------------
   This app has no Turbo and no bundler, so this is a plain IIFE loaded only on
   the Task Manager pages (see tasks/_head.html.erb).

   The contract with the server is one shape, used by every mutation:

       { ok: true, message: "…", regions: { "#tm-region-tasks": "<html>" } }

   The server re-renders the regions its own change touched and this file swaps
   them in by selector. Nothing here patches a row by hand, so the screen can
   never drift out of step with the database — and because every listener is
   delegated from `document`, a swapped region needs no rebinding.
   =========================================================================== */
(function () {
  "use strict";

  var CHART_CDN = "https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.js";

  /* --- small helpers ----------------------------------------------------- */

  function $(selector, root) { return (root || document).querySelector(selector); }
  function $$(selector, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(selector));
  }

  function csrfToken() {
    var meta = $('meta[name="csrf-token"]');
    return meta ? meta.getAttribute("content") : "";
  }

  function notify(message, kind) {
    if (!message) { return; }
    if (window.toastr) {
      toastr[kind === "error" ? "error" : "success"](message);
    } else if (kind === "error") {
      window.alert(message);
    }
  }

  function busy(el, on) {
    if (!el) { return; }
    if (on) { el.setAttribute("data-tm-busy", "1"); } else { el.removeAttribute("data-tm-busy"); }
  }

  /* Every request goes through here so the CSRF token, the XHR header the
     server keys its JSON responses off, and error handling are in one place. */
  function request(url, options) {
    var opts = options || {};
    var headers = {
      "X-Requested-With": "XMLHttpRequest",
      "X-CSRF-Token": csrfToken(),
      Accept: "application/json"
    };
    if (opts.json) { headers["Content-Type"] = "application/json"; }

    return fetch(url, {
      method: opts.method || "GET",
      headers: headers,
      body: opts.body,
      credentials: "same-origin"
    }).then(function (response) {
      var type = response.headers.get("content-type") || "";
      if (type.indexOf("application/json") === -1) {
        // A redirect to the sign-in page, or an error page — either way the
        // session is the likeliest cause and reloading surfaces it honestly.
        if (response.status === 401 || response.redirected) { window.location.reload(); }
        throw new Error("The server returned an unexpected response.");
      }
      return response.json().then(function (payload) {
        if (!response.ok || payload.ok === false) {
          throw new Error(payload.error || "That didn't work. Please try again.");
        }
        return payload;
      });
    });
  }

  /* --- regions ----------------------------------------------------------- */

  function applyRegions(payload) {
    if (!payload || !payload.regions) { return; }
    Object.keys(payload.regions).forEach(function (selector) {
      var target = $(selector);
      if (target) { target.innerHTML = payload.regions[selector]; }
    });
    refresh();
  }

  /* Re-run the pieces that need JS after markup arrives. Idempotent: each
     initialiser marks what it has already claimed. */
  function refresh() {
    startTimers();
    drawCharts();
  }

  /* --- live timers -------------------------------------------------------
     One interval for the whole page rather than one per element, so a long
     session with many rows doesn't accumulate timers. */

  var ticking = [];

  function startTimers() {
    ticking = $$("[data-tm-timer]").map(function (el) {
      return {
        el: el,
        startedAt: new Date(el.getAttribute("data-tm-timer")).getTime(),
        paused: parseInt(el.getAttribute("data-tm-paused"), 10) || 0,
        budget: parseInt(el.getAttribute("data-tm-budget"), 10) || 0,
        style: el.getAttribute("data-tm-style") || "compact"
      };
    });
    tick();
  }

  function tick() {
    ticking.forEach(function (t) {
      var elapsed = Math.max((Date.now() - t.startedAt) / 1000 - t.paused, 0);
      t.el.textContent = formatDuration(elapsed, t.style);
      if (t.budget > 0) { t.el.classList.toggle("tm-timer--over", elapsed > t.budget); }
    });
  }

  function formatDuration(totalSeconds, style) {
    var s = Math.floor(totalSeconds);
    var h = Math.floor(s / 3600);
    var m = Math.floor((s % 3600) / 60);
    var ss = s % 60;

    // "clock"   — the hero: 1:04:22, unmistakably running.
    // "compact" — in a table: 1h 04m 22s, still visibly ticking every second.
    // "short"   — anything stopped, matching the server's hours_label.
    if (style === "clock") {
      return h + ":" + String(m).padStart(2, "0") + ":" + String(ss).padStart(2, "0");
    }
    if (style === "compact") {
      return (h > 0 ? h + "h " + String(m).padStart(2, "0") + "m " : m + "m ") +
             String(ss).padStart(2, "0") + "s";
    }
    return h > 0 ? h + "h " + m + "m" : m + "m";
  }

  setInterval(tick, 1000);

  /* --- charts ------------------------------------------------------------
     Chart.js is fetched on demand: most of the app never renders a chart, so
     it does not belong in the global layout. */

  var chartLoader = null;

  function withChartJs() {
    if (window.Chart) { return Promise.resolve(window.Chart); }
    if (chartLoader) { return chartLoader; }

    chartLoader = new Promise(function (resolve, reject) {
      var script = document.createElement("script");
      script.src = CHART_CDN;
      script.onload = function () { resolve(window.Chart); };
      script.onerror = function () { reject(new Error("chart.js failed to load")); };
      document.head.appendChild(script);
    });
    return chartLoader;
  }

  function chartFont() {
    return '"Inter", -apple-system, "Segoe UI", Roboto, sans-serif';
  }

  function ink(name, fallback) {
    var root = $(".tm");
    if (!root) { return fallback; }
    var value = getComputedStyle(root).getPropertyValue(name);
    return value ? value.trim() : fallback;
  }

  // Only (re)builds a chart whose data has actually changed. Each canvas
  // remembers the spec it was drawn from; a region swap brings in a brand new
  // canvas element, so its chart is built once, while a chart nobody touched
  // is left alone. Without this every tab click, drawer open and filter tore
  // down all four charts and re-animated them.
  function drawCharts() {
    var pending = $$("canvas[data-tm-chart]").filter(function (canvas) {
      return canvas.__tmSpec !== canvas.getAttribute("data-tm-chart");
    });
    if (!pending.length) { return; }

    withChartJs().then(function (Chart) {
      Chart.defaults.font.family = chartFont();
      Chart.defaults.font.size = 11;
      Chart.defaults.color = ink("--tm-ink-3", "#858e9b");

      pending.forEach(function (canvas) {
        var raw = canvas.getAttribute("data-tm-chart");
        var existing = Chart.getChart(canvas);
        if (existing) { existing.destroy(); }

        var spec;
        try { spec = JSON.parse(raw); } catch (e) { return; }
        var builder = charts[spec.kind];
        if (!builder) { return; }

        new Chart(canvas, builder(spec, Chart));
        canvas.__tmSpec = raw;
      });
    }).catch(function () {
      // The table twin under every chart already carries the numbers, so a
      // failed CDN degrades rather than breaks. Show it.
      $$(".tm-datatable[hidden]").forEach(function (table) { table.hidden = false; });
      $$(".tm-chart").forEach(function (box) { box.hidden = true; });
    });
  }

  var grid = function () { return ink("--tm-line", "#e3e7ed"); };

  /* A 2px gap in the surface colour is what separates touching marks — never
     a stroke drawn round them. */
  function stackedBorder() {
    return { borderColor: "#ffffff", borderWidth: 2, borderRadius: 3, borderSkipped: false };
  }

  var tooltipStyle = {
    backgroundColor: "#14161a",
    padding: 10,
    cornerRadius: 6,
    titleFont: { weight: "600", size: 12 },
    bodyFont: { size: 12 },
    displayColors: true,
    boxWidth: 8,
    boxHeight: 8,
    usePointStyle: true
  };

  var charts = {
    /* Workload by executive: who is carrying what, split by status. Horizontal
       because people's names are long, stacked because the split is the point. */
    workload: function (spec) {
      return {
        type: "bar",
        data: {
          labels: spec.labels,
          datasets: spec.series.map(function (s) {
            return Object.assign({
              label: s.label,
              data: s.data,
              backgroundColor: s.color,
              maxBarThickness: 22
            }, stackedBorder());
          })
        },
        options: {
          indexAxis: "y",
          responsive: true,
          maintainAspectRatio: false,
          layout: { padding: { right: 28 } },
          plugins: {
            legend: { display: false },
            tooltip: Object.assign({ mode: "index" }, tooltipStyle)
          },
          scales: {
            x: {
              stacked: true,
              beginAtZero: true,
              grace: "8%",
              ticks: { precision: 0 },
              grid: { color: grid(), drawTicks: false },
              border: { display: false }
            },
            y: {
              stacked: true,
              grid: { display: false },
              ticks: { color: ink("--tm-ink-2", "#4d5560"), font: { size: 12 } },
              border: { display: false }
            }
          }
        },
        plugins: [rowTotalPlugin]
      };
    },

    /* Trend over time, one series — so a sequential hue and no legend box:
       the panel title already says what is plotted. */
    trend: function (spec) {
      return {
        type: "line",
        data: {
          labels: spec.labels,
          datasets: [{
            data: spec.data,
            borderColor: spec.color,
            borderWidth: 2,
            backgroundColor: spec.fill,
            fill: true,
            tension: 0.3,
            pointRadius: 0,
            pointHoverRadius: 5,
            pointHoverBackgroundColor: spec.color,
            pointHoverBorderColor: "#ffffff",
            pointHoverBorderWidth: 2
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          interaction: { mode: "index", intersect: false },
          plugins: {
            legend: { display: false },
            tooltip: Object.assign({
              callbacks: {
                label: function (item) { return " " + item.formattedValue + " " + (spec.unit || ""); }
              }
            }, tooltipStyle)
          },
          scales: {
            x: {
              grid: { display: false },
              ticks: { maxRotation: 0, autoSkipPadding: 12 },
              border: { color: grid() }
            },
            y: {
              beginAtZero: true,
              ticks: { precision: 0, maxTicksLimit: 4 },
              grid: { color: grid(), drawTicks: false },
              border: { display: false }
            }
          }
        }
      };
    },

    /* Ranked magnitude — hours per client. Horizontal because the labels are
       names, with the value written at the tip of each bar. */
    bars: function (spec) {
      return {
        type: "bar",
        data: {
          labels: spec.labels,
          datasets: [{
            data: spec.data,
            backgroundColor: spec.color,
            maxBarThickness: 18,
            borderRadius: { topRight: 4, bottomRight: 4, topLeft: 0, bottomLeft: 0 },
            borderSkipped: false
          }]
        },
        options: {
          indexAxis: "y",
          responsive: true,
          maintainAspectRatio: false,
          layout: { padding: { right: 56 } },
          plugins: {
            legend: { display: false },
            tooltip: Object.assign({
              callbacks: {
                label: function (item) { return " " + (spec.formatted[item.dataIndex] || item.formattedValue); }
              }
            }, tooltipStyle)
          },
          scales: {
            x: { display: false, beginAtZero: true, grace: "5%" },
            y: {
              grid: { display: false },
              ticks: { color: ink("--tm-ink-2", "#4d5560"), font: { size: 12 } },
              border: { display: false }
            }
          }
        },
        plugins: [{
          id: "tmBarValues",
          afterDatasetsDraw: function (chart) {
            var ctx = chart.ctx;
            var meta = chart.getDatasetMeta(0);
            ctx.save();
            ctx.fillStyle = "#4d5560";
            ctx.font = '600 11px ' + chartFont();
            ctx.textAlign = "left";
            ctx.textBaseline = "middle";
            meta.data.forEach(function (bar, i) {
              ctx.fillText(spec.formatted[i] || "", bar.x + 8, bar.y);
            });
            ctx.restore();
          }
        }]
      };
    },

    /* Hours logged per day. Columns, one hue: the job is magnitude, not
       identity. */
    columns: function (spec) {
      return {
        type: "bar",
        data: {
          labels: spec.labels,
          datasets: [{
            data: spec.data,
            backgroundColor: spec.colors || spec.color,
            maxBarThickness: 24,
            borderRadius: { topLeft: 4, topRight: 4, bottomLeft: 0, bottomRight: 0 },
            borderSkipped: false
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            tooltip: Object.assign({
              callbacks: {
                label: function (item) { return " " + (spec.formatted[item.dataIndex] || item.formattedValue); }
              }
            }, tooltipStyle)
          },
          scales: {
            x: { grid: { display: false }, border: { color: grid() } },
            y: {
              beginAtZero: true,
              ticks: {
                maxTicksLimit: 4,
                callback: function (value) { return value + "h"; }
              },
              grid: { color: grid(), drawTicks: false },
              border: { display: false }
            }
          }
        }
      };
    }
  };

  /* Chart.js has no built-in data labels, so this draws the row total at the
     end of each stacked bar. Selective by design — the per-segment values stay
     in the tooltip and the table twin. */
  var rowTotalPlugin = {
    id: "tmRowTotal",
    afterDatasetsDraw: function (chart) {
      var ctx = chart.ctx;
      var totals = [];
      chart.data.datasets.forEach(function (dataset, i) {
        if (chart.getDatasetMeta(i).hidden) { return; }
        dataset.data.forEach(function (value, index) {
          totals[index] = (totals[index] || 0) + (value || 0);
        });
      });

      ctx.save();
      ctx.fillStyle = "#4d5560";
      ctx.font = '600 11px ' + chartFont();
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      var last = chart.getDatasetMeta(chart.data.datasets.length - 1);
      totals.forEach(function (total, index) {
        var bar = last.data[index];
        if (!bar || !total) { return; }
        ctx.fillText(String(total), chart.chartArea.right + 6, bar.y);
      });
      ctx.restore();
    }
  };

  /* --- dragging a card between board columns -----------------------------
     Plain HTML5 drag and drop — no library. The board mirrors the timer state
     machine, so a column that cannot accept the card being dragged is dimmed
     up front instead of rejecting the drop afterwards. Ctrl+Arrow does the
     same thing from the keyboard. */

  // Which columns a card in this state can actually be dropped into. Mirrors
  // TasksController#apply_move — a move the server will refuse is never
  // offered as a target.
  function allowedTargets(status) {
    switch (status) {
      case "pending": return ["in_progress"];
      case "in_progress": return ["paused", "completed"];
      case "paused": return ["in_progress", "completed"];
      default: return [];
    }
  }

  var dragging = null;

  function beginDrag(card) {
    dragging = { card: card, from: card.getAttribute("data-status"), id: card.getAttribute("data-tm-open") };
    card.classList.add("is-dragging");

    var allowed = allowedTargets(dragging.from);
    $$(".tm-col").forEach(function (col) {
      var status = col.getAttribute("data-status");
      if (status !== dragging.from && allowed.indexOf(status) === -1) { col.classList.add("is-blocked"); }
    });
  }

  function endDrag() {
    if (dragging) { dragging.card.classList.remove("is-dragging"); }
    $$(".tm-col").forEach(function (col) { col.classList.remove("is-target", "is-blocked"); });
    var ghost = $(".tm-drop");
    if (ghost) { ghost.remove(); }
    dragging = null;
  }

  function moveTask(taskId, status, card) {
    var board = $("[data-tm-board]");
    var body = document.body;
    if (card) { card.classList.add("is-dragging"); }

    request("/tasks/" + taskId + "/move", {
      method: "PATCH",
      json: true,
      body: JSON.stringify({ status: status, sprint_id: board ? board.getAttribute("data-tm-board") : null })
    }).then(function (payload) {
      applyRegions(payload);
      notify(payload.message);
    }).catch(function (error) {
      if (card) { card.classList.remove("is-dragging"); }
      notify(error.message, "error");
    });
    void body;
  }

  document.addEventListener("dragstart", function (event) {
    var card = event.target.closest(".tm-card");
    if (!card) { return; }
    event.dataTransfer.effectAllowed = "move";
    // Firefox will not start a drag without payload on the transfer.
    event.dataTransfer.setData("text/plain", card.getAttribute("data-tm-open"));
    beginDrag(card);
  });

  document.addEventListener("dragend", endDrag);

  document.addEventListener("dragover", function (event) {
    if (!dragging) { return; }
    var col = event.target.closest(".tm-col");
    if (!col || col.classList.contains("is-blocked")) { return; }

    event.preventDefault();
    event.dataTransfer.dropEffect = "move";

    if (!col.classList.contains("is-target")) {
      $$(".tm-col").forEach(function (c) { c.classList.remove("is-target"); });
      col.classList.add("is-target");

      var ghost = $(".tm-drop") || document.createElement("div");
      ghost.className = "tm-drop";
      $(".tm-col__body", col).appendChild(ghost);
    }
  });

  document.addEventListener("drop", function (event) {
    if (!dragging) { return; }
    var col = event.target.closest(".tm-col");
    if (!col || col.classList.contains("is-blocked")) { return endDrag(); }

    event.preventDefault();
    var status = col.getAttribute("data-status");
    var id = dragging.id;
    var card = dragging.card;
    endDrag();
    if (status !== card.getAttribute("data-status")) { moveTask(id, status, card); }
  });

  // Ctrl/Cmd + Left/Right walks a focused card through the columns it may
  // legally enter, so the board works without a mouse.
  document.addEventListener("keydown", function (event) {
    if (!(event.ctrlKey || event.metaKey)) { return; }
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") { return; }

    var card = document.activeElement && document.activeElement.closest(".tm-card");
    if (!card) { return; }

    var order = ["pending", "in_progress", "paused", "completed"];
    var from = card.getAttribute("data-status");
    var allowed = allowedTargets(from);
    if (!allowed.length) { return; }

    var step = event.key === "ArrowRight" ? 1 : -1;
    var candidates = order.filter(function (s) { return allowed.indexOf(s) !== -1; });
    var target = step > 0
      ? candidates.find(function (s) { return order.indexOf(s) > order.indexOf(from); })
      : candidates.slice().reverse().find(function (s) { return order.indexOf(s) < order.indexOf(from); });
    if (!target) { return; }

    event.preventDefault();
    moveTask(card.getAttribute("data-tm-open"), target, card);
  });

  /* --- the task drawer --------------------------------------------------- */

  var drawer = {
    open: function (taskId) {
      var shell = $("#tm-drawer");
      if (!shell) { return; }
      shell.hidden = false;
      document.body.style.overflow = "hidden";
      var panel = $("#tm-drawer-panel");
      panel.innerHTML = '<div class="tm-empty tm-muted">Loading task…</div>';

      // GET /tasks/:id answers with the drawer's markup, not JSON — it is the
      // one endpoint in the module that returns HTML, because the drawer is a
      // whole rendered panel rather than a field to patch in.
      fetch("/tasks/" + taskId, {
        headers: { "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin"
      }).then(function (response) {
        if (response.status === 401) { window.location.reload(); }
        if (response.status === 403) { throw new Error("You cannot open this task."); }
        if (!response.ok) { throw new Error("This task could not be opened."); }
        return response.text();
      }).then(function (html) {
        panel.innerHTML = html;
        panel.setAttribute("data-task-id", taskId);
        refresh();
        var field = $("#tm-comment-body", panel);
        if (field) { field.focus({ preventScroll: true }); }
      }).catch(function (error) {
        panel.innerHTML = '<div class="tm-empty"><p class="tm-empty__body">' +
          error.message + "</p></div>";
      });
    },

    close: function () {
      var shell = $("#tm-drawer");
      if (!shell || shell.hidden) { return; }
      shell.hidden = true;
      document.body.style.overflow = "";
    },

    isOpen: function () {
      var shell = $("#tm-drawer");
      return shell && !shell.hidden;
    }
  };

  /* --- comments ----------------------------------------------------------
     The thread appends optimistically: the comment appears the instant it is
     sent, greyed, and is replaced by the server's own render on success. */

  function taskIdForComments(el) {
    var panel = el.closest("[data-task-id]");
    return panel ? panel.getAttribute("data-task-id") : null;
  }

  function postComment(form) {
    var taskId = taskIdForComments(form);
    var field = $("#tm-comment-body", form);
    var body = field.value.trim();
    if (!taskId || !body) { return; }

    var thread = $("#tm-thread");
    var pending = document.createElement("div");
    pending.className = "tm-comment is-sending";
    pending.innerHTML = '<span class="tm-avatar">' + (form.getAttribute("data-initials") || "?") +
      '</span><div class="tm-comment__body"><div class="tm-comment__head">' +
      '<span class="tm-comment__who">You</span>' +
      '<span class="tm-comment__when">Sending…</span></div>' +
      '<p class="tm-comment__text"></p></div>';
    $(".tm-comment__text", pending).textContent = body;
    if (thread) { thread.appendChild(pending); }

    field.value = "";
    autosize(field);
    var submit = $("[type=submit]", form);
    busy(submit, true);

    request("/tasks/" + taskId + "/comments", {
      method: "POST",
      json: true,
      body: JSON.stringify({ task_comment: { body: body } })
    }).then(function (payload) {
      pending.outerHTML = payload.html;
      setCommentCount(payload.count, taskId);
    }).catch(function (error) {
      pending.remove();
      field.value = body;
      notify(error.message, "error");
    }).then(function () {
      busy(submit, false);
    });
  }

  // Two places show the size of a thread: the drawer's own tab, and the badge
  // on the row the drawer was opened from. Posting a comment updates both, so
  // the list behind the drawer never shows a stale number.
  function setCommentCount(count, taskId) {
    $$("[data-tm-comment-count]").forEach(function (el) { el.textContent = count; });

    var badge = taskId && $('[data-tm-comment-badge="' + taskId + '"]');
    if (badge) {
      $("[data-tm-comment-badge-value]", badge).textContent = count;
      badge.hidden = count === 0;
      badge.setAttribute("title", count + (count === 1 ? " comment" : " comments"));
    }
  }

  function deleteComment(button) {
    var taskId = taskIdForComments(button);
    var comment = button.closest("[data-comment-id]");
    if (!taskId || !comment) { return; }
    if (!window.confirm("Delete this comment?")) { return; }

    comment.classList.add("is-sending");
    request("/tasks/" + taskId + "/comments/" + comment.getAttribute("data-comment-id"), {
      method: "DELETE"
    }).then(function (payload) {
      comment.remove();
      setCommentCount(payload.count, taskId);
      var thread = $("#tm-thread");
      if (thread && !thread.children.length) {
        thread.innerHTML = '<p class="tm-muted">No comments yet. Start the thread below.</p>';
      }
    }).catch(function (error) {
      comment.classList.remove("is-sending");
      notify(error.message, "error");
    });
  }

  function beginEdit(button) {
    var comment = button.closest("[data-comment-id]");
    var text = $(".tm-comment__text", comment);
    if (!comment || !text || $("form", comment)) { return; }

    var original = text.textContent;
    var form = document.createElement("form");
    form.className = "tm-comment__edit";
    form.innerHTML = '<textarea class="tm-textarea" rows="3"></textarea>' +
      '<div class="tm-composer__row"><span></span><span class="tm-inline">' +
      '<button type="button" class="tm-btn tm-btn--ghost tm-btn--sm" data-tm-cancel-edit>Cancel</button>' +
      '<button type="submit" class="tm-btn tm-btn--primary tm-btn--sm">Save comment</button>' +
      "</span></div>";
    $("textarea", form).value = original;
    text.hidden = true;
    text.insertAdjacentElement("afterend", form);
    $("textarea", form).focus();

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      var body = $("textarea", form).value.trim();
      if (!body) { return; }
      var taskId = taskIdForComments(comment);
      busy($("[type=submit]", form), true);

      request("/tasks/" + taskId + "/comments/" + comment.getAttribute("data-comment-id"), {
        method: "PATCH",
        json: true,
        body: JSON.stringify({ task_comment: { body: body } })
      }).then(function (payload) {
        comment.outerHTML = payload.html;
      }).catch(function (error) {
        busy($("[type=submit]", form), false);
        notify(error.message, "error");
      });
    });

    form.addEventListener("click", function (event) {
      if (event.target.closest("[data-tm-cancel-edit]")) {
        form.remove();
        text.hidden = false;
      }
    });
  }

  function autosize(field) {
    field.style.height = "auto";
    field.style.height = Math.min(field.scrollHeight, 240) + "px";
  }

  /* --- filters -----------------------------------------------------------
     A filter change rewrites the querystring and asks the server for just the
     regions it affects, then pushes the URL so the view is shareable and the
     back button works. */

  function currentView() {
    return $("[data-tm-view]") ? $("[data-tm-view]").getAttribute("data-tm-view") : null;
  }

  function loadFilters(params, regions) {
    var view = currentView();
    if (!view) { return; }

    var url = new URL(window.location.href);
    Object.keys(params).forEach(function (key) {
      if (params[key] === null || params[key] === "") { url.searchParams.delete(key); }
      else { url.searchParams.set(key, params[key]); }
    });

    var panel = $("#tm-region-tasks");
    if (panel) { panel.style.opacity = "0.55"; }

    var fetchUrl = new URL(url.href);
    fetchUrl.searchParams.set("regions", regions || "summary,charts,tasks");

    request(fetchUrl.href).then(function (payload) {
      applyRegions(payload);
      window.history.pushState({}, "", url.href);
    }).catch(function (error) {
      notify(error.message, "error");
    }).then(function () {
      var current = $("#tm-region-tasks");
      if (current) { current.style.opacity = ""; }
    });
  }

  /* --- forms & actions --------------------------------------------------- */

  // A mutation re-renders the regions its change touches, plus whichever heavy
  // tab is actually on screen — so the team-hours matrix is refreshed when you
  // are looking at it and skipped when you are not.
  function withRegions(url) {
    var visible = $$("[data-tm-panel]").filter(function (p) { return !p.hidden; })[0];
    var tab = visible && visible.getAttribute("data-tm-panel");
    if (!tab || tab === "tasks") { return url; }

    var target = new URL(url, window.location.origin);
    target.searchParams.set("regions", "summary,charts,tasks," + tab);
    return target.href;
  }

  function submitAjaxForm(form) {
    var submit = form.querySelector('[type="submit"]:not([disabled])') ||
                 $("[data-tm-default-submit]", form);
    var alertBox = $(".tm-alert", form);
    if (alertBox) { alertBox.classList.remove("is-shown"); }
    busy(submit, true);

    var action = withRegions(form.getAttribute("data-tm-url") || form.action);
    return request(action, { method: (form.getAttribute("data-tm-method") || form.method || "POST").toUpperCase(), body: new FormData(form) })
      .then(function (payload) {
        applyRegions(payload);
        notify(payload.message);
        closeModal(form.closest(".modal"));
        drawer.close();
        if (form.getAttribute("data-tm-reset") !== "false") { form.reset(); }
        return payload;
      })
      .catch(function (error) {
        if (alertBox) {
          $(".tm-alert__text", alertBox).textContent = error.message;
          alertBox.classList.add("is-shown");
        } else {
          notify(error.message, "error");
        }
        throw error;
      })
      .then(function (payload) { busy(submit, false); return payload; },
            function () { busy(submit, false); });
  }

  function closeModal(modal) {
    if (!modal || !window.bootstrap) { return; }
    var instance = bootstrap.Modal.getInstance(modal);
    if (instance) { instance.hide(); }
  }

  function runAction(trigger) {
    var confirmMessage = trigger.getAttribute("data-tm-confirm");
    if (confirmMessage && !window.confirm(confirmMessage)) { return; }

    busy(trigger, true);
    var body = null;
    var payloadAttr = trigger.getAttribute("data-tm-params");
    if (payloadAttr) { body = payloadAttr; }

    request(withRegions(trigger.getAttribute("data-tm-action")), {
      method: (trigger.getAttribute("data-tm-method") || "POST").toUpperCase(),
      json: !!payloadAttr,
      body: body
    }).then(function (payload) {
      applyRegions(payload);
      notify(payload.message);
      if (trigger.getAttribute("data-tm-close-drawer") !== "false") { drawer.close(); }
    }).catch(function (error) {
      notify(error.message, "error");
    }).then(function () {
      busy(trigger, false);
    });
  }

  /* --- the edit / add-subtask form ---------------------------------------
     One form serves both jobs: editing patches /tasks/:id, adding a subtask
     posts to /tasks with a parent_id. The values come from the JSON on the row
     that was clicked, so the page never has to carry a blob of every task. */

  function openTaskForm(options) {
    var modal = $("#tm-task-edit-modal");
    if (!modal || !window.bootstrap) { return; }

    var form = $("#tm-task-edit-form", modal);
    var task = options.task || {};
    var editing = options.mode === "edit";

    form.setAttribute("data-tm-url", editing ? "/tasks/" + options.id : "/tasks");
    $("#tm-task-edit-method", form).value = editing ? "patch" : "post";
    $("#tm-task-edit-heading", modal).textContent = editing ? "Edit task" : "Add a subtask";
    $("#tm-task-edit-submit", modal).textContent = editing ? "Save changes" : "Create subtask";

    var context = $("#tm-task-edit-context", modal);
    context.textContent = editing ? "" : "This becomes a subtask of “" + options.parentTitle + "”.";
    context.hidden = editing;

    $("#tm-task-edit-parent", form).value = editing ? (task.parent_id || "") : options.parentId;

    // A subtask always inherits its parent's sprint, so the control is hidden
    // rather than shown with a value the server will overwrite.
    var isSub = editing ? !!task.parent_id : true;
    $("#tm-task-edit-sprint-wrap", form).hidden = isSub;

    setValue(form, "task[title]", editing ? task.title : "");
    setValue(form, "task[description]", editing ? task.description : "");
    setValue(form, "task[assigned_to_id]", task.assigned_to_id);
    setValue(form, "task[task_type_id]", task.task_type_id);
    setValue(form, "task[sprint_id]", task.sprint_id);
    setValue(form, "task[priority]", editing ? task.priority : "normal");
    setValue(form, "task[due_date]", editing ? task.due_date : "");
    setValue(form, "task[custom_sla_minutes]", editing ? task.custom_sla_minutes : "");

    var alertBox = $(".tm-alert", form);
    if (alertBox) { alertBox.classList.remove("is-shown"); }

    bootstrap.Modal.getOrCreateInstance(modal).show();
  }

  function setValue(form, name, value) {
    var field = form.querySelector('[name="' + name + '"]');
    if (field) { field.value = value == null ? "" : value; }
  }

  /* --- one delegated click listener ------------------------------------- */

  document.addEventListener("click", function (event) {
    var target = event.target;

    var open = target.closest("[data-tm-open]");
    if (open) {
      // The whole row opens the task, but a control sitting inside it — the
      // actions menu, a Start button, a link — keeps its own behaviour. When
      // the clickable element IS the control (a title button, a board card),
      // there is nothing nested and the row wins.
      var control = target.closest("a, button, select, input, textarea, label, .dropdown");
      if (control && control !== open && open.contains(control)) { return; }

      event.preventDefault();
      drawer.open(open.getAttribute("data-tm-open"));
      return;
    }

    if (target.closest("[data-tm-close-drawer-trigger]") ||
        target.classList.contains("tm-drawer__scrim")) {
      event.preventDefault();
      drawer.close();
      return;
    }

    var action = target.closest("[data-tm-action]");
    if (action) {
      event.preventDefault();
      runAction(action);
      return;
    }

    var seg = target.closest("[data-tm-filter]");
    if (seg) {
      event.preventDefault();
      var params = JSON.parse(seg.getAttribute("data-tm-filter"));
      loadFilters(params, seg.getAttribute("data-tm-regions"));
      return;
    }

    var drawerTab = target.closest("[data-tm-drawer-tab]");
    if (drawerTab) {
      event.preventDefault();
      var wanted = drawerTab.getAttribute("data-tm-drawer-tab");
      var panel = $("#tm-drawer-panel");
      $$("[data-tm-drawer-tab]", panel).forEach(function (button) {
        var on = button.getAttribute("data-tm-drawer-tab") === wanted;
        button.classList.toggle("is-active", on);
        button.setAttribute("aria-selected", String(on));
      });
      $$("[data-tm-drawer-panel]", panel).forEach(function (section) {
        section.hidden = section.getAttribute("data-tm-drawer-panel") !== wanted;
      });
      if (wanted === "comments") {
        var field = $("#tm-comment-body", panel);
        if (field) { field.focus({ preventScroll: true }); }
      }
      return;
    }

    var tab = target.closest("[data-tm-tab]");
    if (tab) {
      event.preventDefault();
      selectTab(tab.getAttribute("data-tm-tab"));
      return;
    }

    var reveal = target.closest("[data-tm-reveal]");
    if (reveal) {
      event.preventDefault();
      var table = $(reveal.getAttribute("data-tm-reveal"));
      if (table) {
        table.hidden = !table.hidden;
        reveal.setAttribute("aria-expanded", String(!table.hidden));
        $(".tm-reveal__label", reveal).textContent = table.hidden ? "Show the numbers" : "Hide the numbers";
      }
      return;
    }

    var edit = target.closest("[data-tm-edit]");
    if (edit) {
      event.preventDefault();
      drawer.close();
      openTaskForm({
        mode: "edit",
        id: edit.getAttribute("data-tm-edit"),
        task: JSON.parse(edit.getAttribute("data-task") || "{}")
      });
      return;
    }

    var subtask = target.closest("[data-tm-add-subtask]");
    if (subtask) {
      event.preventDefault();
      drawer.close();
      openTaskForm({
        mode: "subtask",
        parentId: subtask.getAttribute("data-tm-add-subtask"),
        parentTitle: subtask.getAttribute("data-task-title"),
        task: JSON.parse(subtask.getAttribute("data-task") || "{}")
      });
      return;
    }

    if (target.closest("[data-tm-comment-delete]")) {
      event.preventDefault();
      deleteComment(target.closest("[data-tm-comment-delete]"));
      return;
    }

    if (target.closest("[data-tm-comment-edit]")) {
      event.preventDefault();
      beginEdit(target.closest("[data-tm-comment-edit]"));
    }
  });

  document.addEventListener("submit", function (event) {
    var form = event.target;

    if (form.id === "tm-comment-form") {
      event.preventDefault();
      postComment(form);
      return;
    }

    if (form.hasAttribute("data-tm-form")) {
      event.preventDefault();
      submitAjaxForm(form);
    }
  });

  document.addEventListener("change", function (event) {
    var select = event.target.closest("[data-tm-filter-field]");
    if (select) {
      var params = {};
      params[select.getAttribute("data-tm-filter-field")] = select.value;
      loadFilters(params, select.getAttribute("data-tm-regions"));
    }
  });

  /* Cmd/Ctrl+Enter posts a comment — the convention everywhere else a thread
     lives in a panel. Escape closes the drawer. */
  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape" && drawer.isOpen()) {
      drawer.close();
      return;
    }
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      var form = event.target.closest("#tm-comment-form");
      if (form) {
        event.preventDefault();
        postComment(form);
      }
    }
  });

  document.addEventListener("input", function (event) {
    if (event.target.id === "tm-comment-body") { autosize(event.target); }
  });

  /* Search is debounced so a typed word is one request, not eight. */
  var searchTimer = null;
  document.addEventListener("input", function (event) {
    var field = event.target.closest("[data-tm-search]");
    if (!field) { return; }
    clearTimeout(searchTimer);
    searchTimer = setTimeout(function () {
      loadFilters({ q: field.value.trim() }, "tasks");
    }, 300);
  });

  // Back and forward restore the view the same way a filter builds it, so
  // stepping through history costs a region swap rather than a full reload.
  window.addEventListener("popstate", function () {
    if (!currentView()) { return; }
    drawer.close();

    var url = new URL(window.location.href);
    url.searchParams.set("regions", currentView() === "my_tasks" ? "focus,summary,tasks" : "summary,charts,tasks");

    request(url.href)
      .then(applyRegions)
      .then(function () {
        var tab = new URL(window.location.href).searchParams.get("tab");
        if (tab && $('[data-tm-tab="' + tab + '"]')) { selectTab(tab, { push: false }); }
      })
      .catch(function () { window.location.reload(); });
  });

  /* --- tabs -------------------------------------------------------------- */

  // Purely client side: every panel is already on the page, so switching is a
  // hidden-attribute flip and never a request.
  function selectTab(name, options) {
    var opts = options || {};

    $$("[data-tm-tab]").forEach(function (button) {
      var on = button.getAttribute("data-tm-tab") === name;
      button.setAttribute("aria-selected", String(on));
      button.classList.toggle("is-active", on);
    });
    $$("[data-tm-panel]").forEach(function (panel) {
      panel.hidden = panel.getAttribute("data-tm-panel") !== name;
    });

    if (opts.push !== false) {
      var url = new URL(window.location.href);
      url.searchParams.set("tab", name);
      window.history.replaceState({}, "", url.href);
    }
    refresh();
  }

  /* --- task type picker, in the new-task form --------------------------- */

  document.addEventListener("change", function (event) {
    var select = event.target.closest("[data-tm-type-select]");
    if (!select) { return; }

    var option = select.options[select.selectedIndex];
    var isNew = select.value === "__new__";
    var wrapper = $("#tm-new-type");
    var nameField = $("#tm-new-type-name");
    if (wrapper) {
      wrapper.hidden = !isNew;
      if (nameField) { nameField.required = isNew; }
    }

    var minutes = isNew ? NaN : parseInt(option && option.getAttribute("data-sla"), 10);
    var slaField = $("#tm-sla");
    var hint = $("#tm-sla-hint");
    if (slaField && hint) {
      if (isNaN(minutes)) {
        hint.textContent = "";
      } else {
        if (!slaField.value) { slaField.value = minutes; }
        var h = Math.floor(minutes / 60);
        hint.textContent = "This type's default budget is " +
          (h > 0 ? h + "h " : "") + (minutes % 60) + "m.";
      }
    }

    var describe = $("#tm-type-description");
    if (describe) {
      describe.textContent = isNew ? "" : ((option && option.getAttribute("data-description")) || "");
    }
  });

  /* --- the pause dialog --------------------------------------------------
     One dialog serves every running task; the button that opened it says
     which task and where to post. */

  document.addEventListener("click", function (event) {
    var trigger = event.target.closest("[data-tm-pause-url]");
    if (!trigger) { return; }

    var form = $("#tm-pause-form");
    if (!form) { return; }
    form.setAttribute("data-tm-url", trigger.getAttribute("data-tm-pause-url"));
    $("#tm-pause-context").textContent =
      "“" + trigger.getAttribute("data-tm-pause-title") + "” stops counting until you resume it.";
    $("#tm-pause-reason").value = "";
    var alertBox = $(".tm-alert", form);
    if (alertBox) { alertBox.classList.remove("is-shown"); }
  });

  /* --- CSV import preview ----------------------------------------------- */

  document.addEventListener("click", function (event) {
    var button = event.target.closest("[data-tm-preview]");
    if (!button) { return; }
    event.preventDefault();

    var form = button.closest("form");
    var target = $("#tm-import-preview");
    if (!form || !target) { return; }

    busy(button, true);
    target.innerHTML = "";
    request(button.getAttribute("data-tm-preview"), { method: "POST", body: new FormData(form) })
      .then(function (payload) { target.innerHTML = payload.html; })
      .catch(function (error) { notify(error.message, "error"); })
      .then(function () { busy(button, false); });
  });

  /* --- boot -------------------------------------------------------------- */

  function boot() {
    if (!$(".tm")) { return; }
    refresh();
    var tab = new URL(window.location.href).searchParams.get("tab");
    if (tab && $('[data-tm-tab="' + tab + '"]')) { selectTab(tab); }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
}());
