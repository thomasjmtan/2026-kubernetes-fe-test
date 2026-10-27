// Kanso: small, quiet interactions.

(function () {
  const root = document.documentElement;

  // Theme: remembered per browser, falls back to system preference.
  try {
    const saved = localStorage.getItem("kanso-theme");
    if (saved) root.dataset.theme = saved;
  } catch (_) {}

  document.querySelector(".theme-toggle").addEventListener("click", () => {
    const isDark = root.dataset.theme
      ? root.dataset.theme === "dark"
      : matchMedia("(prefers-color-scheme: dark)").matches;
    root.dataset.theme = isDark ? "light" : "dark";
    try { localStorage.setItem("kanso-theme", root.dataset.theme); } catch (_) {}
  });

  // Tokyo clock.
  const clock = document.getElementById("clock");
  const fmt = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Tokyo", hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false,
  });
  const tick = () => { clock.textContent = fmt.format(new Date()); };
  tick();
  setInterval(tick, 1000);

  // Status board: gently jitter latencies so the board feels alive.
  const cells = document.querySelectorAll("[data-latency]");
  const updated = document.getElementById("board-updated");
  let last = Date.now();
  setInterval(() => {
    cells.forEach((cell) => {
      const base = Number(cell.dataset.latency);
      const next = Math.max(1, Math.round(base + (Math.random() - 0.5) * base * 0.2));
      cell.textContent = next + " ms";
    });
    last = Date.now();
  }, 5000);
  setInterval(() => {
    const s = Math.round((Date.now() - last) / 1000);
    updated.textContent = s < 2 ? "just now" : s + "s ago";
  }, 1000);

  // Version: written at build time to /version.txt.
  const version = document.getElementById("version");
  fetch("/version.txt", { cache: "no-store" })
    .then((r) => { if (!r.ok) throw new Error(r.status); return r.text(); })
    .then((t) => { version.textContent = t.trim() || "dev"; })
    .catch(() => { version.textContent = "dev"; });

  // Access form: client-side only.
  const form = document.querySelector(".join-form");
  const msg = document.querySelector(".form-msg");
  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const email = form.email.value.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      msg.textContent = "Please enter a valid email address.";
      msg.classList.add("error");
      return;
    }
    msg.classList.remove("error");
    msg.textContent = "ありがとう. We'll be in touch, quietly.";
    form.reset();
  });

  // Dashboard cube: still until asked, then a 90° turn that comes to rest square.
  // Turns are about the viewer's axes, so "right" always rolls the front face right.
  // The orientation matrix only ever holds 0 / ±1, so it never drifts off square.
  const scene = document.querySelector(".cube-scene");
  const cube = scene.querySelector(".cube");
  const TURNS = {
    right: [[0, 0, 1], [0, 1, 0], [-1, 0, 0]],   // rotateY(90deg)
    left: [[0, 0, -1], [0, 1, 0], [1, 0, 0]],    // rotateY(-90deg)
    up: [[1, 0, 0], [0, 0, -1], [0, 1, 0]],      // rotateX(90deg)
    down: [[1, 0, 0], [0, 0, 1], [0, -1, 0]],    // rotateX(-90deg)
  };
  let orient = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
  let turning = false;

  const multiply = (a, b) => a.map((row) => b[0].map((_, j) => row.reduce((sum, v, k) => sum + v * b[k][j], 0)));
  const render = () => {
    const c = (j) => [orient[0][j], orient[1][j], orient[2][j], 0];   // matrix3d is column-major
    cube.style.transform = `rotateX(-22deg) rotateY(32deg) matrix3d(${[...c(0), ...c(1), ...c(2), 0, 0, 0, 1].join(",")})`;
  };
  const turn = (dir) => {
    if (turning) return;
    orient = multiply(TURNS[dir], orient);
    render();
    const ms = parseFloat(getComputedStyle(cube).transitionDuration) * 1000;
    if (ms > 0) {
      turning = true;
      setTimeout(() => { turning = false; }, ms);
    }
  };
  // Which edge of the scene the pointer is nearest to.
  const edgeAt = (e) => {
    const r = scene.getBoundingClientRect();
    const dx = (e.clientX - r.left) / r.width - 0.5;
    const dy = (e.clientY - r.top) / r.height - 0.5;
    if (Math.abs(dx) > Math.abs(dy)) return dx > 0 ? "right" : "left";
    return dy > 0 ? "down" : "up";
  };

  render();
  scene.addEventListener("click", (e) => turn(edgeAt(e)));
  scene.addEventListener("pointermove", (e) => { scene.dataset.hover = edgeAt(e); });
  scene.addEventListener("pointerleave", () => { delete scene.dataset.hover; });
  scene.addEventListener("keydown", (e) => {
    const dir = { ArrowRight: "right", ArrowLeft: "left", ArrowUp: "up", ArrowDown: "down" }[e.key];
    if (!dir) return;
    e.preventDefault();
    turn(dir);
  });

  // Reveal sections on scroll.
  const targets = document.querySelectorAll(".section-head, .principle, .stop, .board, .cube-stage, .join-inner");
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15 });
    targets.forEach((t) => { t.classList.add("reveal"); io.observe(t); });
  }
})();
