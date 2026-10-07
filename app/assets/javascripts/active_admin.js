//= require active_admin/base
function formatDuration(seconds) {
  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  return `${hrs}h ${mins}m ${secs}s`;
}
function updateLiveDurations() {
  const now = Math.floor(Date.now() / 1000);

  document.querySelectorAll('.live-duration').forEach(span => {
    const clockIn = parseInt(span.dataset.clockIn, 10);
    const breaks = JSON.parse(span.dataset.breaks || '[]');

    let totalBreak = 0;
    for (let br of breaks) {
      const brIn = br.in || 0;
      const brOut = br.out || now;
      if (brIn < now) {
        totalBreak += Math.min(brOut, now) - brIn;
      }
    }

    const workingSeconds = now - clockIn - totalBreak;
    span.textContent = formatDuration(workingSeconds);
  });
}

document.addEventListener("DOMContentLoaded", function () {
  setInterval(updateLiveDurations, 1000);
});

  document.addEventListener('DOMContentLoaded', function () {
    $('.select2-filter').select2({
      placeholder: 'Select an option',
      allowClear: true,
      width: 'resolve'
    });
  });

// === Quadroots admin: brand block — clock-tower icon + wordmark =============
document.addEventListener('DOMContentLoaded', function () {
  // Native markup is <h1#site_title><img></h1> (or wrapped in <a> if a
  // site_title_link is configured); append the wordmark to whichever exists.
  var brandHost = document.querySelector('#header h1#site_title a') ||
                  document.querySelector('#header h1#site_title');
  if (!brandHost || brandHost.querySelector('.qr-brand-lines')) return;

  var clockTower =
    '<svg class="qr-brand-clock" viewBox="0 0 24 24" fill="none" ' +
    'stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M8 21V9l4-5 4 5v12"></path>' +    // tower body + pointed roof
    '<path d="M6 21h12"></path>' +              // base
    '<circle cx="12" cy="12" r="2.4"></circle>' + // clock face
    '<path d="M12 12V10.6M12 12l1.3.9"></path>' + // hands
    '</svg>';

  var clock = document.createElement('span');
  clock.className = 'qr-brand-clock-wrap';
  clock.innerHTML = clockTower;

  var lines = document.createElement('span');
  lines.className = 'qr-brand-lines';
  lines.innerHTML =
    '<span class="qr-brand-name">Clock Tower</span>' +
    '<span class="qr-brand-sub">Quadroots Tracker</span>';

  brandHost.appendChild(clock);
  brandHost.appendChild(lines);

  // Menu button for small screens, where the sidebar folds into a top bar.
  var navToggle = document.createElement('button');
  navToggle.type = 'button';
  navToggle.className = 'qr-nav-toggle';
  navToggle.setAttribute('aria-label', 'Menu');
  navToggle.setAttribute('aria-expanded', 'false');
  navToggle.innerHTML =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">' +
    '<line x1="4" y1="7" x2="20" y2="7"></line><line x1="4" y1="12" x2="20" y2="12"></line>' +
    '<line x1="4" y1="17" x2="20" y2="17"></line></svg>';
  navToggle.addEventListener('click', function () {
    var isOpen = document.body.classList.toggle('nav-open');
    navToggle.setAttribute('aria-expanded', String(isOpen));
  });
  document.querySelector('#header h1#site_title').appendChild(navToggle);
});

// === Quadroots admin: flatpickr date / date-time / month pickers =============
// Replaces jQuery UI's datepicker (class "datepicker": leave forms and the
// date-range filters) and the browser's native datetime-local / month fields.
// The real input keeps the value format Rails expects; flatpickr shows a
// friendlier one in a visible "alt" field.
(function () {
  function initPickers(root) {
    if (typeof flatpickr === 'undefined') return;   // CDN blocked: native fields still work

    root.querySelectorAll('input.datepicker:not(.flatpickr-input)').forEach(function (input) {
      input.classList.add('hasDatepicker');          // tells ActiveAdmin not to attach jQuery UI
      flatpickr(input, {
        dateFormat: 'Y-m-d', altInput: true, altFormat: 'd M Y', altInputClass: 'qr-date-field',
        allowInput: false, disableMobile: true
      });
    });

    root.querySelectorAll('input[type="datetime-local"]:not(.flatpickr-input)').forEach(function (input) {
      flatpickr(input, {
        enableTime: true, minuteIncrement: 1,
        dateFormat: 'Y-m-d\\TH:i', altInput: true, altFormat: 'd M Y, h:i K', altInputClass: 'qr-date-field',
        // Rails may render seconds ("...T01:56:00"); let the browser parse either form.
        parseDate: function (value) { return new Date(value); },
        disableMobile: true
      });
    });

    if (typeof monthSelectPlugin !== 'undefined') {
      root.querySelectorAll('input[type="month"]:not(.flatpickr-input)').forEach(function (input) {
        flatpickr(input, {
          altInput: true, altInputClass: (input.className + ' qr-date-field').trim(), disableMobile: true,
          plugins: [new monthSelectPlugin({ shorthand: true, dateFormat: 'Y-m', altFormat: 'F Y' })]
        });
      });
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    initPickers(document);
    // Rows added with "Add new ..." in a has_many form (e.g. breaks on a time clock).
    if (window.jQuery) {
      jQuery(document).on('has_many_add:after', function (e, fieldset) { initPickers(fieldset[0] || document); });
    }
  });
})();

// === Quadroots admin: charts ================================================
// Any element with data-chart='{"kind": ...}' becomes an ApexCharts chart. The
// library is fetched only when a page actually has one. Kinds: "columns"
// (optionally stacked), "area", "hbar", "donut", "spark".
(function () {
  var APEX_SRC = 'https://cdn.jsdelivr.net/npm/apexcharts@3.54.1/dist/apexcharts.min.js';
  var INK = '#09090B', MUTED = '#71717A', GRID = '#ECECF2';

  function options(spec) {
    var unit = spec.unit || '';
    var value = function (v) { return v === null || v === undefined ? 'No data' : v + unit; };
    var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var n = (spec.categories || []).length;

    var o = {
      chart: {
        type: 'bar', height: spec.height || 280, fontFamily: 'Inter, sans-serif', parentHeightOffset: 0,
        toolbar: { show: false }, zoom: { enabled: false }, stacked: !!spec.stacked,
        animations: { enabled: !reduce, easing: 'easeout', speed: 550 }
      },
      colors: spec.colors,
      series: spec.series,
      dataLabels: { enabled: false },
      // A legend only when there is more than one series to tell apart.
      legend: {
        show: (spec.series || []).length > 1, position: 'top', horizontalAlign: 'left', fontSize: '12.5px',
        fontWeight: 500, labels: { colors: MUTED }, markers: { width: 8, height: 8, radius: 8 },
        itemMargin: { horizontal: 10, vertical: 4 }
      },
      grid: { borderColor: GRID, padding: { left: 6, right: 6, top: -8 }, xaxis: { lines: { show: false } } },
      states: { hover: { filter: { type: 'darken', value: 0.92 } }, active: { filter: { type: 'none' } } },
      tooltip: { theme: 'light', style: { fontSize: '12.5px', fontFamily: 'Inter, sans-serif' }, y: { formatter: value } },
      xaxis: {
        categories: spec.categories,
        tickAmount: n > 14 ? 10 : undefined,
        labels: { rotate: 0, hideOverlappingLabels: true, style: { colors: MUTED, fontSize: '12px' } },
        axisBorder: { show: false }, axisTicks: { show: false }, tooltip: { enabled: false }
      },
      yaxis: { labels: { style: { colors: MUTED, fontSize: '12px' }, formatter: function (v) { return Math.round(v * 10) / 10 + unit; } } }
    };

    if (spec.kind === 'columns') {
      o.plotOptions = { bar: { columnWidth: n > 20 ? '70%' : '48%', borderRadius: 4, borderRadiusApplication: 'end', borderRadiusWhenStacked: 'last' } };
      // A thin surface-coloured gap keeps stacked segments apart.
      o.stroke = { show: !!spec.stacked, width: 2, colors: ['#FFFFFF'] };
      o.tooltip.shared = true; o.tooltip.intersect = false;
    } else if (spec.kind === 'hbar') {
      o.plotOptions = { bar: { horizontal: true, barHeight: '56%', borderRadius: 4, borderRadiusApplication: 'end', dataLabels: { position: 'top' } } };
      o.dataLabels = { enabled: true, textAnchor: 'start', offsetX: 26, formatter: value, style: { colors: [INK], fontSize: '12px', fontWeight: 600 } };
      o.grid.xaxis = { lines: { show: true } }; o.grid.yaxis = { lines: { show: false } };
      o.grid.padding.right = 44;
      o.xaxis.labels.formatter = function (v) { return v + unit; };
      o.yaxis = { labels: { style: { colors: INK, fontSize: '12.5px' }, maxWidth: 170 } };
    } else if (spec.kind === 'area') {
      o.chart.type = 'area';
      o.stroke = { curve: 'smooth', width: 2 };
      o.fill = { type: 'gradient', gradient: { shadeIntensity: 1, opacityFrom: 0.28, opacityTo: 0.02, stops: [0, 95] } };
      o.markers = { size: 0, strokeColors: '#FFFFFF', strokeWidth: 2, hover: { size: 5 } };
    } else if (spec.kind === 'donut') {
      o.chart.type = 'donut';
      o.series = spec.values; o.labels = spec.categories;
      o.stroke = { width: 2, colors: ['#FFFFFF'] };
      o.legend = { show: true, position: 'bottom', fontSize: '12.5px', fontWeight: 500, labels: { colors: MUTED },
                   markers: { width: 8, height: 8, radius: 8 }, itemMargin: { horizontal: 8, vertical: 4 },
                   formatter: function (name, ctx) { return name + ' · ' + ctx.w.globals.series[ctx.seriesIndex]; } };
      o.plotOptions = { pie: { donut: { size: '70%', labels: {
        show: true,
        name: { fontSize: '12.5px', color: MUTED, offsetY: 18 },
        value: { fontSize: '26px', fontWeight: 600, color: INK, offsetY: -14 },
        total: { show: true, label: spec.total_label || 'Total', fontSize: '12.5px', color: MUTED }
      } } } };
      delete o.xaxis; delete o.yaxis; delete o.grid;
    } else if (spec.kind === 'spark') {
      o.chart.type = 'area'; o.chart.sparkline = { enabled: true };
      o.stroke = { curve: 'smooth', width: 2 };
      o.fill = { type: 'gradient', gradient: { shadeIntensity: 1, opacityFrom: 0.35, opacityTo: 0, stops: [0, 100] } };
      o.tooltip.x = { show: true }; o.tooltip.marker = { show: false };
    }
    return o;
  }

  var charts = [];
  var loading = false;

  function render() {
    // Charts whose element was replaced (the dashboard swaps its content
    // every 15 seconds) are destroyed so they do not pile up.
    charts = charts.filter(function (entry) {
      if (document.body.contains(entry.el)) return true;
      try { entry.chart.destroy(); } catch (e) { /* already gone */ }
      return false;
    });

    document.querySelectorAll('[data-chart]:not([data-chart-ready])').forEach(function (el) {
      el.setAttribute('data-chart-ready', '');
      try {
        var o = options(JSON.parse(el.getAttribute('data-chart')));
        if (window.qrChartsQuiet) o.chart.animations = { enabled: false };
        var chart = new ApexCharts(el, o);
        chart.render();
        charts.push({ el: el, chart: chart });
      } catch (e) { if (window.console) console.error('Chart failed to render', e); }
    });
  }

  // Also called by partials that are loaded or refreshed after the page is up.
  window.qrRenderCharts = function () {
    if (!document.querySelector('[data-chart]:not([data-chart-ready])')) return;
    if (window.ApexCharts) return render();
    if (loading) return;            // render() runs for everything once it arrives
    loading = true;
    var script = document.createElement('script');
    script.src = APEX_SRC;
    script.onload = render;
    document.head.appendChild(script);
  };

  document.addEventListener('DOMContentLoaded', window.qrRenderCharts);
})();

// === Quadroots admin: signed-in admin card in the sidebar ====================
document.addEventListener('DOMContentLoaded', function () {
  var user = document.querySelector('#utility_nav #current_user > a');
  if (user && !user.querySelector('.qr-user-avatar')) {
    var email = user.textContent.trim();
    user.textContent = '';
    var avatar = document.createElement('span');
    avatar.className = 'qr-user-avatar';
    avatar.setAttribute('aria-hidden', 'true');
    avatar.textContent = email.charAt(0);
    var label = document.createElement('span');
    label.className = 'qr-user-email';
    label.textContent = email;
    user.title = email;
    user.appendChild(avatar);
    user.appendChild(label);
  }
  var logout = document.querySelector('#utility_nav #logout > a');
  if (logout) {
    logout.setAttribute('aria-label', 'Sign out');
    logout.title = 'Sign out';
  }
});

// === Quadroots admin: fold each row's action links into a "more" menu ========
// A row with six action links used to stack them and grow ~150px tall. The
// links are moved (not copied) into a menu on <body>, so their data-method /
// data-confirm behaviour from rails-ujs keeps working unchanged.
document.addEventListener('DOMContentLoaded', function () {
  var open = null;

  function close() {
    if (!open) return;
    open.menu.classList.remove('open');
    open.button.setAttribute('aria-expanded', 'false');
    open = null;
  }

  function show(button, menu) {
    close();
    menu.classList.add('open');
    var rect = button.getBoundingClientRect();
    var top = rect.bottom + 4;
    if (top + menu.offsetHeight > window.innerHeight - 8) top = Math.max(8, rect.top - menu.offsetHeight - 4);
    menu.style.top = top + 'px';
    menu.style.left = Math.max(8, rect.right - menu.offsetWidth) + 'px';
    button.setAttribute('aria-expanded', 'true');
    open = { button: button, menu: menu };
  }

  document.querySelectorAll('table.index_table td.col-actions').forEach(function (cell) {
    // Remember where "View" goes before the links leave the row: clicking
    // anywhere on the row opens it (see "clickable rows" below).
    // Tables with custom actions may not mark a link as view_link; fall back
    // to the first plain link (never one that changes data).
    var view = cell.querySelector('a.view_link') || cell.querySelector('a:not(.btn):not([data-method])');
    if (view && cell.parentElement) cell.parentElement.setAttribute('data-href', view.getAttribute('href'));

    var links = Array.prototype.filter.call(cell.querySelectorAll('a'), function (a) {
      return !a.classList.contains('btn');
    });
    if (links.length < 2) return;

    var menu = document.createElement('div');
    menu.className = 'row-menu';
    menu.setAttribute('role', 'menu');
    // Destructive actions last, below the divider.
    links.sort(function (a, b) {
      return (a.dataset.method === 'delete' ? 1 : 0) - (b.dataset.method === 'delete' ? 1 : 0);
    });
    links.forEach(function (a) {
      a.className = '';
      a.setAttribute('role', 'menuitem');
      if (a.title) a.textContent = a.title;
      a.removeAttribute('title');
      menu.appendChild(a);
    });
    document.body.appendChild(menu);

    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'row-menu-toggle';
    button.setAttribute('aria-label', 'Row actions');
    button.setAttribute('aria-haspopup', 'menu');
    button.setAttribute('aria-expanded', 'false');
    button.innerHTML =
      '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' +
      '<circle cx="5" cy="12" r="1.8"></circle><circle cx="12" cy="12" r="1.8"></circle>' +
      '<circle cx="19" cy="12" r="1.8"></circle></svg>';
    cell.appendChild(button);

    button.addEventListener('click', function (e) {
      e.stopPropagation();
      if (open && open.button === button) { close(); } else { show(button, menu); }
    });
    button.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowDown') { e.preventDefault(); show(button, menu); menu.querySelector('a').focus(); }
    });
    menu.addEventListener('keydown', function (e) {
      var items = Array.prototype.slice.call(menu.querySelectorAll('a'));
      var i = items.indexOf(document.activeElement);
      if (e.key === 'ArrowDown') { e.preventDefault(); items[(i + 1) % items.length].focus(); }
      if (e.key === 'ArrowUp') { e.preventDefault(); items[(i - 1 + items.length) % items.length].focus(); }
      if (e.key === 'Escape') { close(); button.focus(); }
    });
  });

  document.addEventListener('click', function (e) {
    if (open && !open.menu.contains(e.target)) close();
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') close(); });
  window.addEventListener('scroll', close, true);
  window.addEventListener('resize', close);
});

// === Quadroots admin: clickable rows ========================================
// Anything carrying data-href (index table rows get it from their View link;
// custom pages set it themselves) opens that page when clicked. Controls
// inside the row keep their own behaviour, and selecting text does not navigate.
document.addEventListener('DOMContentLoaded', function () {
  var INTERACTIVE = 'a, button, input, select, textarea, label, summary, details, .col-selectable, .col-actions';

  document.querySelectorAll('[data-href]').forEach(function (row) {
    row.classList.add('is-clickable');
    row.setAttribute('tabindex', '0');
    row.setAttribute('role', 'link');
  });

  function go(row, newTab) {
    var href = row.getAttribute('data-href');
    if (!href) return;
    if (newTab) { window.open(href, '_blank', 'noopener'); } else { window.location.href = href; }
  }

  document.addEventListener('click', function (e) {
    var row = e.target.closest && e.target.closest('[data-href]');
    if (!row || e.target.closest(INTERACTIVE)) return;
    if (String(window.getSelection && window.getSelection()).length > 0) return;
    go(row, e.metaKey || e.ctrlKey);
  });
  // Middle click opens in a new tab, like a link.
  document.addEventListener('auxclick', function (e) {
    var row = e.target.closest && e.target.closest('[data-href]');
    if (row && e.button === 1 && !e.target.closest(INTERACTIVE)) { e.preventDefault(); go(row, true); }
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && e.target.matches && e.target.matches('[data-href]')) go(e.target, e.metaKey || e.ctrlKey);
  });
});

// === Quadroots admin: collapsible sidebar groups (e.g. Settings) =============
document.addEventListener('DOMContentLoaded', function () {
  var KEY = 'qrAdminCollapsedGroups';
  var collapsed = [];
  try { collapsed = JSON.parse(localStorage.getItem(KEY)) || []; } catch (e) { collapsed = []; }

  document.querySelectorAll('#header ul.tabs > li.has_nested').forEach(function (group) {
    var heading = group.querySelector(':scope > a[href="#"]');
    if (!heading) return;
    var id = group.id || heading.textContent.trim();

    // Never hide the group that contains the page you are on.
    var open = group.classList.contains('current') || collapsed.indexOf(id) === -1;
    group.classList.toggle('collapsed', !open);
    heading.setAttribute('role', 'button');
    heading.setAttribute('aria-expanded', String(open));

    heading.addEventListener('click', function (e) {
      e.preventDefault();
      var nowCollapsed = group.classList.toggle('collapsed');
      heading.setAttribute('aria-expanded', String(!nowCollapsed));
      collapsed = collapsed.filter(function (g) { return g !== id; });
      if (nowCollapsed) collapsed.push(id);
      try { localStorage.setItem(KEY, JSON.stringify(collapsed)); } catch (err) { /* private mode */ }
    });
  });
});

// === Quadroots admin: full-width tables + off-canvas filters drawer ==========
document.addEventListener('DOMContentLoaded', function () {
  // 1) Wrap every index table so a wide table scrolls on its own,
  //    instead of forcing a horizontal scrollbar on the whole page.
  document.querySelectorAll('table.index_table').forEach(function (table) {
    if (table.parentElement && table.parentElement.classList.contains('table-scroll')) return;
    var wrap = document.createElement('div');
    wrap.className = 'table-scroll';
    table.parentNode.insertBefore(wrap, table);
    wrap.appendChild(table);
  });

  // 2) Turn the filter sidebar into a toggled slide-in drawer (index pages only)
  var sidebar = document.getElementById('sidebar');
  if (!sidebar || !document.body.classList.contains('index')) return;

  var backdrop = document.createElement('div');
  backdrop.className = 'filters-backdrop';
  document.body.appendChild(backdrop);

  var titleBar = document.createElement('div');
  titleBar.className = 'filters-drawer-title';
  titleBar.innerHTML = '<span>Filters</span>';
  var closeBtn = document.createElement('button');
  closeBtn.type = 'button';
  closeBtn.className = 'filters-close';
  closeBtn.setAttribute('aria-label', 'Close filters');
  closeBtn.innerHTML = '&times;';
  titleBar.appendChild(closeBtn);
  sidebar.insertBefore(titleBar, sidebar.firstChild);

  var toggle = document.createElement('button');
  toggle.type = 'button';
  toggle.className = 'filters-toggle';
  toggle.innerHTML =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
    'stroke-linecap="round" stroke-linejoin="round">' +
    '<polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"></polygon></svg>' +
    '<span>Filters</span>';
  var host = document.querySelector('.table_tools') ||
             document.querySelector('#title_bar #titlebar_right') ||
             document.querySelector('#title_bar');
  if (host) host.appendChild(toggle);

  function closeDrawer() { document.body.classList.remove('filters-open'); }
  toggle.addEventListener('click', function () { document.body.classList.toggle('filters-open'); });
  closeBtn.addEventListener('click', closeDrawer);
  backdrop.addEventListener('click', closeDrawer);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeDrawer(); });
});

