// Upstream Google Analytics snippet removed when vendoring.
// Must remain a callable no-op: bundle.js calls ga() from the
// transport-control handlers, so an undefined ga breaks play,
// step and reset.
window.ga = function () {};
