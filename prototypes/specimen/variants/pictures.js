// PROTOTYPE, round 24, sz-rs30.1.83.19.9, look "pic-scrim": measure the blurred picture under the name block and set
// the scrim alpha so the facts line reaches 4.5:1 and the name 3:1 (large text) on the brightest pixels there
// (7:1 and 4.5:1 in Increase Contrast).
"use strict";
(() => {
  const lin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  const lum = ([r, g, b]) => 0.2126 * lin(r / 255) + 0.7152 * lin(g / 255) + 0.0722 * lin(b / 255);
  const ratio = (a, b) => (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  // Any CSS colour to sRGB bytes: the browser resolves it on a canvas, whatever format getComputedStyle returns.
  const probe = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
  function rgbOf(css) {
    probe.clearRect(0, 0, 1, 1);
    probe.fillStyle = "#000";
    probe.fillStyle = css;
    probe.fillRect(0, 0, 1, 1);
    return [...probe.getImageData(0, 0, 1, 1).data.slice(0, 3)];
  }

  // A failed measurement leaves the scrim nearly solid: unreadable text is the worse failure.
  function fallback(head, why) {
    const hero = document.querySelector(".hero");
    hero.style.setProperty("--scrim-a", "0.9");
    hero.style.setProperty("--scrim-rgb", rgbOf(getComputedStyle(head).getPropertyValue("--color-background-page")).join(" "));
    tag(`scrim 90%, not measured: ${why}`);
  }

  // The specimen shows the measurement on the picture, so Flo sees it on the phone.
  function tag(text) {
    let t = document.querySelector(".scrim-tag");
    if (!t) {
      t = document.createElement("div");
      t.className = "scrim-tag";
      document.querySelector(".hero .pic").append(t);
    }
    t.textContent = text;
  }

  function measure(shown, img, head) {
    const box = shown.getBoundingClientRect(), hb = head.getBoundingClientRect();
    const iw = img.naturalWidth, ih = img.naturalHeight;
    if (!iw || !box.height) return fallback(head, "no size");
    // object-fit: cover at object-position 50% 22%, as person.html sets it.
    const s = Math.max(box.width / iw, box.height / ih);
    const ox = (box.width - iw * s) * 0.5, oy = (box.height - ih * s) * 0.22;
    const x0 = (hb.left - box.left - ox) / s, x1 = (hb.right - box.left - ox) / s;
    const y0 = (hb.top - box.top - 8 - oy) / s, y1 = (box.bottom - box.top - oy) / s;
    // Sample at one pixel per 6 points, then average blocks of 5 by 5: a 30 point cell stands in for the 16 pt blur.
    const K = 5, W = Math.max(K * 2, Math.round((hb.right - hb.left) / 6)), H = Math.max(K, Math.round(W * (y1 - y0) / (x1 - x0)));
    const c = document.createElement("canvas");
    c.width = W; c.height = H;
    const ctx = c.getContext("2d");
    try { ctx.drawImage(img, x0, y0, x1 - x0, y1 - y0, 0, 0, W, H); } catch { return fallback(head, "draw"); }
    let px;
    try { px = ctx.getImageData(0, 0, W, H).data; } catch { return fallback(head, "blocked"); }
    const ys = [];
    for (let cy = 0; cy + K <= H; cy += K) for (let cx = 0; cx + K <= W; cx += K) {
      // Light adds in linear space, so the blur averages linear luminance.
      let sum = 0;
      for (let y = cy; y < cy + K; y++) for (let x = cx; x < cx + K; x++) { const i = (y * W + x) * 4; sum += lum([px[i], px[i + 1], px[i + 2]]); }
      ys.push(sum / (K * K));
    }
    ys.sort((a, b) => a - b);
    // The brightest blurred cell decides.
    const worst = ys[ys.length - 1];

    const scrim = rgbOf(getComputedStyle(head).getPropertyValue("--color-background-page"));
    const meta = head.querySelector(".meta"), title = head.querySelector("h1");
    const yMeta = lum(rgbOf(getComputedStyle(meta).color)), yTitle = lum(rgbOf(getComputedStyle(title).color));
    const yScrim = lum(scrim);
    // Increase Contrast asks AAA: 7:1 for the facts, 4.5:1 for the large name.
    const high = document.documentElement.dataset.contrast === "high";
    const tMeta = high ? 7 : 4.5, tTitle = high ? 4.5 : 3;
    let a = 0;
    // Compositing is linear in light: the pixel under the scrim is mixed toward the scrim colour.
    for (; a <= 1; a += 0.02) {
      const y = worst * (1 - a) + yScrim * a;
      if (ratio(yMeta, y) >= tMeta && ratio(yTitle, y) >= tTitle) break;
    }
    a = Math.min(1, Math.max(a, 0.25));
    const hero = document.querySelector(".hero");
    hero.style.setProperty("--scrim-a", a.toFixed(2));
    hero.style.setProperty("--scrim-rgb", scrim.join(" "));
    head.dataset.scrim = `scrim ${Math.round(a * 100)}%, brightest ${worst.toFixed(2)}`;
    tag(`scrim ${Math.round(a * 100)}%, measured`);
  }

  // The name block takes the dark room's tokens; data-contrast follows the switch.
  function darken(head) {
    head.dataset.theme = "dark";
    head.dataset.contrast = document.documentElement.dataset.contrast;
  }

  const wait = setInterval(() => {
    const img = document.querySelector(".hero .pic img"), head = document.querySelector(".hero .person-head");
    if (!head) return;
    if (!img) { clearInterval(wait); return; }
    clearInterval(wait);
    darken(head);
    // Measure a fresh copy: the shown image may come from a cache entry fetched without CORS.
    const copy = new Image();
    copy.crossOrigin = "anonymous";
    let ready = false;
    const run = () => { if (ready) measure(img, copy, head); };
    copy.onload = () => { ready = true; run(); };
    copy.onerror = () => fallback(head, "load");
    copy.src = img.src + (img.src.includes("?") ? "&" : "?") + "measure=1";
    new ResizeObserver(run).observe(head);
    new MutationObserver(() => { darken(head); run(); }).observe(document.documentElement, { attributes: true, attributeFilter: ["data-contrast", "data-theme"] });
  }, 50);
})();
