const sprayField = document.querySelector('.spray-field');
if (sprayField) {
  const colors = ['#ff1f8f', '#ffd60a', '#38bdf8', '#00f5d4', '#845ef7', '#ff6f59'];
  const sprayCount = 26;
  for (let i = 0; i < sprayCount; i += 1) {
    const spray = document.createElement('span');
    spray.className = 'spray';
    const color = colors[Math.floor(Math.random() * colors.length)];
    const size = Math.random() * 140 + 80;
    spray.style.setProperty('--color', color);
    spray.style.setProperty('--size', `${size}px`);
    spray.style.setProperty('--top', `${Math.random() * 100}%`);
    spray.style.setProperty('--left', `${Math.random() * 100}%`);
    spray.style.setProperty('--scale', `${Math.random() * 0.6 + 0.7}`);
    spray.style.setProperty('--rotate', `${Math.random() * 90 - 45}deg`);
    spray.style.setProperty('--delay', `${Math.random() * 3}`);
    sprayField.appendChild(spray);
  }
}

const highlight = document.querySelector('[data-highlight]');
if (highlight) {
  const phrases = ['living graffiti', 'neon canvases', 'AR murals', 'collab drops'];
  let index = 0;
  highlight.classList.add('pop');
  setInterval(() => {
    index = (index + 1) % phrases.length;
    highlight.classList.remove('pop');
    highlight.textContent = phrases[index];
    // Trigger reflow so animation can replay
    void highlight.offsetWidth;
    highlight.classList.add('pop');
  }, 3800);
}

const yearTarget = document.querySelector('[data-year]');
if (yearTarget) {
  yearTarget.textContent = new Date().getFullYear();
}
