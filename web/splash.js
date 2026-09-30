// Removes the HTML loading splash once Flutter paints its first frame.
window.addEventListener('flutter-first-frame', function () {
  var s = document.getElementById('splash');
  if (s) s.remove();
});
