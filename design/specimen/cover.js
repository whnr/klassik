// The player page while it plays (ADR 0034, sz-rs30.1.83.19.7).
// Only the page of what plays changes (.app.is-player); an album page that does not play stays a plain page.
// The cover room, the default: the page ground takes the cover's hue; text and the accent are solved again for that ground.
// The hall, a setting: the page sits in the dark room, a step darker, lit by a glow in the cover's hue.
// In the cover room the timeline and the playing row take a mark colour from the cover; controls keep the accent.

(() => {
  // The specimen pill sets the setting as data-player on the root.
  const look = "player-" + (document.documentElement.dataset.player === "hall" ? "hall" : "room");

  // ---------- OKLab ----------
  const lin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  const enc = (c) => {
    c = Math.min(Math.max(c, 0), 1);
    return c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055;
  };
  function toLab([r, g, b]) {
    [r, g, b] = [r, g, b].map((v) => lin(v / 255));
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return [
      0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
    ];
  }
  function linOf(L, C, h) {
    const a = C * Math.cos((h * Math.PI) / 180),
      b = C * Math.sin((h * Math.PI) / 180);
    const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3,
      m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3,
      s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
    return [
      4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
    ];
  }
  function rgbOf(L, C, h) {
    while (C > 0 && linOf(L, C, h).some((v) => v < -1e-4 || v > 1 + 1e-4)) C -= 0.002;
    return linOf(L, Math.max(C, 0), h).map((v) => Math.round(enc(v) * 255));
  }
  const lch = (rgb) => {
    const [L, a, b] = toLab(rgb);
    return [L, Math.hypot(a, b), ((Math.atan2(b, a) * 180) / Math.PI + 360) % 360];
  };
  const lum = ([r, g, b]) => 0.2126 * lin(r / 255) + 0.7152 * lin(g / 255) + 0.0722 * lin(b / 255);
  const ratio = (x, y) => {
    const [a, b] = [lum(x), lum(y)].sort((p, q) => q - p);
    return (a + 0.05) / (b + 0.05);
  };
  const css = (rgb) => `rgb(${rgb.join(" ")})`;
  const parse = (v) => {
    v = v.trim();
    if (v.startsWith("#")) return [1, 3, 5].map((i) => parseInt(v.slice(i, i + 2), 16));
    return v
      .match(/[\d.]+/g)
      .slice(0, 3)
      .map(Number);
  };
  // The lightness nearest the start that reaches the target on the ground, moving away from the ground.
  function solve([L0, C, h], ground, target) {
    const dir = lum(ground) < 0.18 ? 1 : -1;
    let L = L0;
    if (ratio(rgbOf(L, C, h), ground) >= target) return rgbOf(L, C, h);
    for (; L >= 0 && L <= 1; L += 0.005 * dir) if (ratio(rgbOf(L, C, h), ground) >= target) break;
    return rgbOf(Math.min(Math.max(L, 0), 1), C, h);
  }

  // ---------- The cover's colour: the strongest hue family, not the average ----------
  // The average of a painting is mud. Bin the chromatic pixels by hue, weight by chroma, take the heaviest bin.
  function coverHue(album) {
    const c = K.cover(album, 250);
    if (!c) return Promise.resolve(null);
    return new Promise((resolve) => {
      const img = new Image();
      img.crossOrigin = "anonymous";
      img.onload = () => {
        try {
          const cv = document.createElement("canvas");
          cv.width = cv.height = 32;
          const ctx = cv.getContext("2d");
          ctx.drawImage(img, 0, 0, 32, 32);
          const px = ctx.getImageData(0, 0, 32, 32).data;
          const bins = Array.from({ length: 24 }, () => ({ w: 0, a: 0, b: 0, L: 0 }));
          for (let i = 0; i < px.length; i += 4) {
            const [L, a, b] = toLab([px[i], px[i + 1], px[i + 2]]);
            const C = Math.hypot(a, b);
            if (C < 0.03 || L < 0.15 || L > 0.96) continue;
            const bin = bins[Math.floor((((Math.atan2(b, a) * 180) / Math.PI + 360) % 360) / 15)];
            bin.w += C;
            bin.a += a * C;
            bin.b += b * C;
            bin.L += L * C;
          }
          const best = bins.reduce((p, q) => (q.w > p.w ? q : p));
          if (best.w < 0.6) return resolve(null);
          const a = best.a / best.w,
            b = best.b / best.w;
          resolve({ C: Math.hypot(a, b), h: ((Math.atan2(b, a) * 180) / Math.PI + 360) % 360 });
        } catch {
          resolve(null);
        }
      };
      img.onerror = () => resolve(null);
      img.src = c.url;
    });
  }

  const app = () => document.querySelector(".app");
  const dark = () => document.documentElement.dataset.theme === "dark";
  const high = () => document.documentElement.dataset.contrast === "high";

  // A grey cover gives no hue; it takes Klassik's accent, as the cover-colour research says.
  function accentHue() {
    const [, C, h] = lch(parse(getComputedStyle(document.documentElement).getPropertyValue("--color-tint")));
    return { C, h };
  }

  let room = null;
  async function apply() {
    const a = app();
    if (!a) return;
    const playing = a.classList.contains("is-player");
    if (look === "player-hall") {
      // The room changes before the colours resolve, so the cover light below reads the hall's tokens.
      // Setting the room fires the observer below, so only a change sets it.
      const want = playing ? "dark" : null;
      if (want !== room) {
        room = want;
        K.setRoom(want);
      }
    }
    // The values go on the root: the timeline and the scrub label sit outside the app frame.
    const r = document.documentElement;
    const props = [
      "--color-background-page",
      "--color-background-grouped",
      "--color-background-row",
      "--color-text-secondary",
      "--color-tint",
      "--color-timeline-played",
      "--color-timeline-unplayed",
      "--cover-mark",
      "--cover-light",
      "--edge-colour",
      "--color-favourite",
      "--color-favourite-off",
    ];
    props.forEach((p) => {
      r.style.removeProperty(p);
    });
    if (!playing) return;
    const item = K.current();
    const hue = (item && (await coverHue(item.album))) || accentHue();
    const root = getComputedStyle(r);
    const ground0 = parse(root.getPropertyValue("--color-background-page"));

    if (look === "player-hall") {
      // The cover lights the hall: a glow of its hue behind the cover, nothing else.
      // The hall is a step darker than the dark room of other pages, never black.
      const [L, C, h] = lch(ground0);
      const hall = rgbOf(Math.max(L - 0.035, 0.15), C, h);
      for (const p of [
        "--color-background-page",
        "--color-background-grouped",
        "--color-background-row",
        "--edge-colour",
      ])
        r.style.setProperty(p, css(hall));
      r.style.setProperty("--cover-light", css(rgbOf(0.42, Math.min(hue.C, 0.12), hue.h)));
      return;
    }
    let ground = ground0;
    if (look === "player-room") {
      ground = dark()
        ? rgbOf(0.235, Math.min(hue.C, 0.04), hue.h)
        : rgbOf(high() ? 0.95 : 0.935, Math.min(hue.C, high() ? 0.018 : 0.026), hue.h);
      for (const p of [
        "--color-background-page",
        "--color-background-grouped",
        "--color-background-row",
        "--edge-colour",
      ])
        r.style.setProperty(p, css(ground));
      const t = high() ? 7 : 4.6;
      r.style.setProperty(
        "--color-text-secondary",
        css(solve(lch(parse(root.getPropertyValue("--color-text-secondary"))), ground, t)),
      );
      r.style.setProperty("--color-tint", css(solve(lch(parse(root.getPropertyValue("--color-tint"))), ground, t)));
      r.style.setProperty(
        "--color-favourite",
        css(
          solve(
            lch(parse(root.getPropertyValue("--color-favourite") || root.getPropertyValue("--color-tint"))),
            ground,
            high() ? 7 : 4.5,
          ),
        ),
      );
      r.style.setProperty("--color-timeline-unplayed", css(rgbOf(dark() ? 0.36 : 0.8, Math.min(hue.C, 0.03), hue.h)));
      // The quiet off state is solved on the page ground; on the cover ground Increase Contrast solves it again.
      if (high())
        r.style.setProperty(
          "--color-favourite-off",
          css(solve(lch(parse(root.getPropertyValue("--color-favourite-off"))), ground, 4.5)),
        );
    }
    // The mark colour: the cover's hue at a strong chroma, 3:1 on the ground (4.5:1 in Increase Contrast).
    const start = dark() ? 0.7 : 0.55;
    let mark = solve([start, Math.min(Math.max(hue.C, 0.09), 0.14), hue.h], ground, high() ? 4.5 : 3);
    // Increase Contrast: the played part also stands 4.5:1 apart from the unplayed part beside it.
    if (high()) mark = solve(lch(mark), parse(getComputedStyle(r).getPropertyValue("--color-timeline-unplayed")), 4.5);
    r.style.setProperty("--cover-mark", css(mark));
    r.style.setProperty("--color-timeline-played", css(mark));
  }

  const wait = setInterval(() => {
    const a = app();
    if (!a || !document.querySelector(".page-body")) return;
    clearInterval(wait);
    a.dataset.look = look;
    let busy = false;
    const run = async () => {
      if (busy) return;
      busy = true;
      try {
        await apply();
      } finally {
        busy = false;
      }
    };
    run();
    new MutationObserver(run).observe(a, { attributes: true, attributeFilter: ["class"] });
    new MutationObserver(() => setTimeout(run, 0)).observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme", "data-contrast", "data-accent", "data-player"],
    });
  }, 50);
})();
