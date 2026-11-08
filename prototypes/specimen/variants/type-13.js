// Section headings in sentence case: the specimen pages write them in capitals for the old grouped style.
// The page name lets the CSS keep inset lists in Settings only.
document.documentElement.dataset.page = location.pathname.split("/").pop().replace(".html", "") || "index";
(() => {
  const sentence = (node) => {
    for (const t of node.querySelectorAll ? [node, ...node.querySelectorAll("*")] : []) {
      for (const c of t.childNodes) if (c.nodeType === 3 && /^[A-ZÀ-Ž\s]{3,}$/.test(c.textContent.trim())) {
        const s = c.textContent.toLowerCase(); c.textContent = s.replace(/\S/, (x) => x.toUpperCase());
      }
    }
  };
  new MutationObserver((list) => list.forEach((m) => m.addedNodes.forEach((n) => n.nodeType === 1 && n.querySelectorAll(".section-head").forEach(sentence))))
    .observe(document.documentElement, { childList: true, subtree: true });
})();
