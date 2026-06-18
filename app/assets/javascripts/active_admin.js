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

