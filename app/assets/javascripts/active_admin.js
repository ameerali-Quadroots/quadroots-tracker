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
