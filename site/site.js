(() => {
  'use strict';
  const root = document.documentElement;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const stage = document.querySelector('.icon-stage');
  const icon = stage.querySelector('.icon-exit');
  const tones = [...document.querySelectorAll('[data-tone]')].map(element => ({element, hsl: element.dataset.tone.split(',').map(Number)}));
  const drifting = [...document.querySelectorAll('.icon-orbits,.closing-orbit,.pad-demo,.settings-shot')];
  const masthead = document.querySelector('.masthead');
  const download = document.querySelector('.header-download');
  const language = document.querySelector('.language-picker');
  root.classList.add('js');

  Promise.all([...stage.querySelectorAll('img')].map(image => image.decode())).then(() => stage.classList.add('art-ready'));

  function scrollArt() {
    const view = innerHeight;
    let color = tones[0].hsl;
    for (const {element, hsl} of tones.slice(1)) {
      const phase = Math.min(1, Math.max(0, (view * .85 - element.getBoundingClientRect().top) / (view * .7)));
      const blend = phase * phase * (3 - 2 * phase);
      color = color.map((value, axis) => value + (hsl[axis] - value) * blend);
    }
    root.style.setProperty('--paper', `hsl(${color[0]} ${color[1]}% ${color[2]}%)`);
    root.style.setProperty('--header-ink', color[2] < 68 ? '#fff' : '#16151f');
    for (const element of drifting) {
      const rect = element.getBoundingClientRect();
      const offset = Math.max(-1, Math.min(1, (rect.top + rect.height / 2 - view / 2) / view));
      element.style.setProperty('--drift', `${reduced.matches ? 0 : offset * 24}px`);
    }
    const hero = tones[0].element.getBoundingClientRect();
    const exit = reduced.matches ? 0 : Math.min(1, Math.max(0, -hero.top / (hero.height * .8)));
    icon.style.transform = `translate3d(${exit * 35}px,${exit * -100}px,0) scale(${1 - exit * .22}) rotate(${exit * 12}deg)`;
    icon.style.opacity = String(1 - exit);
  }
  let frame = 0;
  addEventListener('scroll', () => { frame ||= requestAnimationFrame(() => { frame = 0; scrollArt(); }); }, {passive: true});
  addEventListener('resize', scrollArt);
  reduced.addEventListener('change', scrollArt);
  scrollArt();

  const visibleDownloads = new Set();
  const downloads = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (entry.intersectionRatio >= .9) visibleDownloads.add(entry.target); else visibleDownloads.delete(entry.target);
    }
    download.hidden = visibleDownloads.size > 0;
  }, {rootMargin: `-${masthead.offsetHeight}px 0px 0px`, threshold: .9});
  document.querySelectorAll('.download-button').forEach(button => downloads.observe(button));

  new IntersectionObserver(entries => {
    stage.classList.toggle('in-view', entries[0].isIntersecting);
  }).observe(stage);
  const demos = new IntersectionObserver(entries => {
    for (const entry of entries) entry.target.classList.toggle('playing', entry.intersectionRatio >= .45);
  }, {threshold: .45});
  document.querySelectorAll('.pad-demo').forEach(demo => demos.observe(demo));

  document.addEventListener('visibilitychange', () => document.body.classList.toggle('page-hidden', document.hidden));
  document.addEventListener('click', event => {
    if (!language.contains(event.target)) language.open = false;
  });
  language.addEventListener('keydown', event => {
    if (event.key === 'Escape') { language.open = false; language.querySelector('summary').focus(); }
  });
})();
