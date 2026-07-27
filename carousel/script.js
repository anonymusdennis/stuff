(function () {
  const INTERVAL_MS = 5000;
  const SWIPE_THRESHOLD = 50;

  const track = document.getElementById('carousel-track');
  const slides = Array.from(track.querySelectorAll('.carousel__slide'));
  const dotsContainer = document.getElementById('carousel-dots');
  const btnPrev = document.getElementById('btn-prev');
  const btnNext = document.getElementById('btn-next');
  const btnPlay = document.getElementById('btn-play');
  const progressBar = document.getElementById('progress-bar');

  let current = 0;
  let playing = true;
  let timer = null;
  let progressRAF = null;
  let progressStart = 0;
  let touchStartX = 0;

  slides.forEach((_, i) => {
    const dot = document.createElement('button');
    dot.className = 'carousel__dot' + (i === 0 ? ' is-active' : '');
    dot.type = 'button';
    dot.setAttribute('role', 'tab');
    dot.setAttribute('aria-label', `Bild ${i + 1} anzeigen`);
    dot.setAttribute('aria-selected', i === 0 ? 'true' : 'false');
    dot.addEventListener('click', () => goTo(i));
    dotsContainer.appendChild(dot);
  });

  const dots = Array.from(dotsContainer.querySelectorAll('.carousel__dot'));

  function goTo(index) {
    current = ((index % slides.length) + slides.length) % slides.length;

    slides.forEach((slide, i) => {
      slide.classList.toggle('is-active', i === current);
    });

    dots.forEach((dot, i) => {
      dot.classList.toggle('is-active', i === current);
      dot.setAttribute('aria-selected', i === current ? 'true' : 'false');
    });

    resetProgress();
  }

  function next() {
    goTo(current + 1);
  }

  function prev() {
    goTo(current - 1);
  }

  function resetProgress() {
    cancelAnimationFrame(progressRAF);
    progressBar.style.width = '0%';
    if (playing) startProgress();
  }

  function startProgress() {
    progressStart = performance.now();

    function tick(now) {
      const elapsed = now - progressStart;
      const pct = Math.min((elapsed / INTERVAL_MS) * 100, 100);
      progressBar.style.width = pct + '%';

      if (pct < 100) {
        progressRAF = requestAnimationFrame(tick);
      }
    }

    progressRAF = requestAnimationFrame(tick);
  }

  function startAutoplay() {
    stopAutoplay();
    timer = setInterval(next, INTERVAL_MS);
    startProgress();
  }

  function stopAutoplay() {
    clearInterval(timer);
    cancelAnimationFrame(progressRAF);
    timer = null;
  }

  function togglePlay() {
    playing = !playing;
    btnPlay.classList.toggle('is-paused', !playing);
    btnPlay.setAttribute('aria-label', playing ? 'Automatische Wiedergabe pausieren' : 'Automatische Wiedergabe starten');
    btnPlay.setAttribute('aria-pressed', playing ? 'true' : 'false');

    if (playing) {
      startAutoplay();
    } else {
      stopAutoplay();
    }
  }

  btnPrev.addEventListener('click', () => { prev(); if (playing) startAutoplay(); });
  btnNext.addEventListener('click', () => { next(); if (playing) startAutoplay(); });
  btnPlay.addEventListener('click', togglePlay);

  document.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowLeft') { prev(); if (playing) startAutoplay(); }
    if (e.key === 'ArrowRight') { next(); if (playing) startAutoplay(); }
  });

  track.addEventListener('touchstart', (e) => {
    touchStartX = e.changedTouches[0].screenX;
  }, { passive: true });

  track.addEventListener('touchend', (e) => {
    const diff = touchStartX - e.changedTouches[0].screenX;
    if (Math.abs(diff) < SWIPE_THRESHOLD) return;
    diff > 0 ? next() : prev();
    if (playing) startAutoplay();
  }, { passive: true });

  const carousel = document.querySelector('.carousel');
  carousel.addEventListener('mouseenter', () => { if (playing) stopAutoplay(); });
  carousel.addEventListener('mouseleave', () => { if (playing) startAutoplay(); });

  startAutoplay();
})();
