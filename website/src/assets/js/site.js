// Audra — comportamento do site. Sem dependências; tudo é progressivo (a página funciona sem JS).
(() => {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---- Navigation: scrolled state, mobile menu, current section --------------------------------
  const nav = document.querySelector("[data-nav]");
  const toggle = document.querySelector("[data-nav-toggle]");
  const onScroll = () => nav && nav.classList.toggle("is-scrolled", window.scrollY > 8);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  const setMenu = (open) => {
    if (!nav || !toggle) return;
    nav.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", String(open));
    toggle.setAttribute("aria-label", open ? "Fechar menu" : "Abrir menu");
  };
  toggle?.addEventListener("click", () => setMenu(!nav.classList.contains("is-open")));
  document.querySelectorAll(".nav-links a").forEach((a) => a.addEventListener("click", () => setMenu(false)));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") setMenu(false); });

  const links = new Map();
  document.querySelectorAll('.nav-links a[href*="#"]').forEach((a) => links.set(a.hash.slice(1), a));
  if ("IntersectionObserver" in window && links.size) {
    const sections = [...links.keys()].map((id) => document.getElementById(id)).filter(Boolean);
    const spy = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        const link = links.get(entry.target.id);
        if (!link) return;
        if (entry.isIntersecting) {
          links.forEach((l) => l.removeAttribute("aria-current"));
          link.setAttribute("aria-current", "true");
        }
      });
    }, { rootMargin: "-45% 0px -50% 0px" });
    sections.forEach((s) => spy.observe(s));
  }

  // ---- Reveal on scroll ------------------------------------------------------------------------
  const revealables = document.querySelectorAll("[data-reveal]");
  if (reduceMotion || !("IntersectionObserver" in window)) {
    revealables.forEach((el) => el.classList.add("is-visible"));
  } else {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    revealables.forEach((el) => observer.observe(el));
  }

  // ---- Hero screenshot straightens as you scroll -----------------------------------------------
  const visual = document.querySelector("[data-hero-visual]");
  if (visual && !reduceMotion) {
    let ticking = false;
    const update = () => {
      ticking = false;
      const rect = visual.getBoundingClientRect();
      const progress = Math.min(1, Math.max(0, 1 - (rect.top - window.innerHeight * 0.18) / (window.innerHeight * 0.62)));
      visual.style.setProperty("--tilt", `${(14 * (1 - progress)).toFixed(2)}deg`);
      visual.style.setProperty("--scale", (0.96 + 0.04 * progress).toFixed(4));
    };
    update();
    window.addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
    window.addEventListener("resize", update, { passive: true });
  }

  // ---- Release: refresh from GitHub so a new version appears without rebuilding the site -------
  const months = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];
  const formatDate = (iso) => {
    const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
    return `${d} de ${months[m - 1]} de ${y}`;
  };
  const formatSize = (bytes) => `${(bytes / 1048576).toFixed(1).replace(".", ",")} MB`;

  let initial = {};
  try { initial = JSON.parse(document.getElementById("release-data")?.textContent || "{}"); } catch {}
  const repo = "steinertruthy/audra";
  const asset = "Audra.dmg";

  const apply = (release) => {
    document.querySelectorAll("[data-release-version]").forEach((el) => {
      el.textContent = el.closest(".pill") ? `v${release.version}` : release.version;
    });
    document.querySelectorAll("[data-release-version-link]").forEach((el) => { el.textContent = `v${release.version}`; });
    document.querySelectorAll("[data-release-date]").forEach((el) => { el.textContent = formatDate(release.date); });
    document.querySelectorAll("[data-release-size]").forEach((el) => { el.textContent = formatSize(release.size); });
    document.querySelectorAll("[data-release]").forEach((el) => { el.dataset.state = "available"; });
    document.querySelectorAll("[data-release-download]").forEach((el) => {
      el.href = release.downloadUrl;
      el.removeAttribute("aria-disabled");
      el.lastChild.textContent = " Baixar Audra.dmg";
    });
    document.querySelectorAll("[data-release-status]").forEach((el) => {
      el.dataset.state = "available";
      el.textContent = "Versão estável mais recente";
    });
    if (release.sha256) {
      document.querySelectorAll("[data-release-sha]").forEach((el) => { el.textContent = release.sha256; });
      document.querySelectorAll("[data-release-checksum]").forEach((el) => { el.hidden = false; });
    }
  };

  const cacheKey = "audra-release-v1";
  const fromCache = () => {
    try {
      const cached = JSON.parse(sessionStorage.getItem(cacheKey) || "null");
      if (cached && Date.now() - cached.at < 10 * 60 * 1000) return cached.release;
    } catch {}
    return undefined;
  };

  const refresh = async () => {
    const cached = fromCache();
    if (cached !== undefined) { if (cached) apply(cached); return; }
    try {
      const response = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, { headers: { Accept: "application/vnd.github+json" } });
      let release = null;
      if (response.ok) {
        const data = await response.json();
        const dmg = (data.assets || []).find((a) => a.name === asset);
        if (dmg) {
          release = {
            version: data.tag_name.replace(/^v/, ""),
            date: (data.published_at || "").slice(0, 10),
            downloadUrl: dmg.browser_download_url,
            size: dmg.size,
            sha256: initial.version === data.tag_name.replace(/^v/, "") ? initial.sha256 : "",
          };
        }
      }
      try { sessionStorage.setItem(cacheKey, JSON.stringify({ at: Date.now(), release })); } catch {}
      if (release) apply(release);
    } catch {
      // Offline or rate limited: the version rendered at build time stays on the page.
    }
  };

  if (document.querySelector("[data-release]") || document.querySelector("[data-release-version]")) refresh();

})();
