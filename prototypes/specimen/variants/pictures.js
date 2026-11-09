// PROTOTYPE, round 24, sz-rs30.1.83.19.9, look "pic-scrim": measure the picture under the name block and set the
// scrim alpha so the facts line reaches 4.5:1 and the name 3:1 (large text) on the brightest pixels there.
"use strict";
(() => {
  const lin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  const lum = ([r, g, b]) => 0.2126 * lin(r / 255) + 0.7152 * lin(g / 255) + 0.0722 * lin(b / 255);
  const ratio = (a, b) => (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  const rgbOf = (css) => css.match(/[\d.]+/g).slice(0, 3).map(Number);

  function measure(img, head) {
    const box = img.getBoundingClientRect(), hb = head.getBoundingClientRect();
    const iw = img.naturalWidth, ih = img.naturalHeight;
    if (!iw || !box.height) return;
    // object-fit: cover at object-position 50% 22%, as person.html sets it.
    const s = Math.max(box.width / iw, box.height / ih);
    const ox = (box.width - iw * s) * 0.5, oy = (box.height - ih * s) * 0.22;
    const x0 = (hb.left - box.left - ox) / s, x1 = (hb.right - box.left - ox) / s;
    const y0 = (hb.top - box.top - 8 - oy) / s, y1 = (box.bottom - box.top - oy) / s;
    const W = 48, H = Math.max(8, Math.round(W * (y1 - y0) / (x1 - x0)));
    const c = document.createElement("canvas");
    c.width = W; c.height = H;
    const ctx = c.getContext("2d");
    try { ctx.drawImage(img, x0, y0, x1 - x0, y1 - y0, 0, 0, W, H); } catch { return; }
    let px;
    try { px = ctx.getImageData(0, 0, W, H).data; } catch { return; }
    const ys = [];
    for (let i = 0; i < px.length; i += 4) ys.push(lum([px[i], px[i + 1], px[i + 2]]));
    ys.sort((a, b) => a - b);
    // The 98th percentile: a lone highlight pixel does not decide, a white collar does.
    const worst = ys[Math.floor(ys.length * 0.98)];

    const cs = getComputedStyle(head);
    const scrim = rgbOf(cs.getPropertyValue("--color-background-page").trim().startsWith("#")
      ? hexRgb(cs.getPropertyValue("--color-background-page").trim()) : cs.getPropertyValue("--color-background-page"));
    const meta = head.querySelector(".meta"), title = head.querySelector("h1");
    const yMeta = lum(rgbOf(getComputedStyle(meta).color)), yTitle = lum(rgbOf(getComputedStyle(title).color));
    const yScrim = lum(scrim);
    let a = 0;
    // Compositing is linear in light: the pixel under the scrim is mixed toward the scrim colour.
    for (; a <= 1; a += 0.02) {
      const y = worst * (1 - a) + yScrim * a;
      if (ratio(yMeta, y) >= 4.5 && ratio(yTitle, y) >= 3) break;
    }
    a = Math.min(1, Math.max(a, 0.25));
    const hero = document.querySelector(".hero");
    hero.style.setProperty("--scrim-a", a.toFixed(2));
    hero.style.setProperty("--scrim-rgb", scrim.join(" "));
    head.dataset.scrim = `scrim ${Math.round(a * 100)}%, brightest ${worst.toFixed(2)}`;
  }

  function hexRgb(h) { return `rgb(${[1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)).join(",")})`; }

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
    const run = () => measure(img, head);
    if (img.complete) run(); else img.addEventListener("load", run);
    new ResizeObserver(run).observe(head);
    new MutationObserver(() => { darken(head); run(); }).observe(document.documentElement, { attributes: true, attributeFilter: ["data-contrast", "data-theme"] });
  }, 50);
})();
