// Zoom on the Mermaid diagrams: a click opens the diagram in full screen, the wheel zooms
// around the pointer, a drag pans, a double click or 0 resets, Escape closes. The theme
// renders the diagram in a closed shadow root, so the diagram itself is moved into the
// overlay and scaled with a CSS transform, then put back when the overlay closes.
(function () {
  "use strict";

  var overlay, stage, current, placeholder;
  var scale = 1, x = 0, y = 0;

  function label(key) {
    var fr = document.documentElement.lang === "fr";
    return {
      open: fr ? "Agrandir le diagramme" : "Enlarge the diagram",
      close: fr ? "Fermer" : "Close",
      reset: fr ? "Taille initiale" : "Reset",
      help: fr ? "Molette : zoom · glisser : déplacer · Échap : fermer"
               : "Wheel: zoom · drag: pan · Escape: close"
    }[key];
  }

  function apply() {
    stage.style.transform = "translate(" + x + "px," + y + "px) scale(" + scale + ")";
  }

  function fit() {
    // Fit the diagram in the overlay, at most twice its size in the page
    var box = overlay.getBoundingClientRect();
    var w = current.offsetWidth, h = current.offsetHeight;
    scale = Math.min((box.width - 48) / w, (box.height - 96) / h, 2);
    x = (box.width - w * scale) / 2;
    y = (box.height - h * scale) / 2 + 24;
    apply();
  }

  function zoomAt(factor, cx, cy) {
    var next = Math.min(Math.max(scale * factor, 0.2), 10);
    x = cx - (cx - x) * (next / scale);
    y = cy - (cy - y) * (next / scale);
    scale = next;
    apply();
  }

  function build() {
    overlay = document.createElement("div");
    overlay.className = "mermaid-zoom";
    overlay.hidden = true;
    overlay.innerHTML =
      '<div class="mermaid-zoom__bar">' +
      '<span class="mermaid-zoom__help"></span>' +
      '<button type="button" data-zoom="in" aria-label="+">+</button>' +
      '<button type="button" data-zoom="out" aria-label="-">−</button>' +
      '<button type="button" data-zoom="reset"></button>' +
      '<button type="button" data-zoom="close"></button>' +
      "</div>" +
      '<div class="mermaid-zoom__stage"></div>';
    document.body.appendChild(overlay);
    stage = overlay.querySelector(".mermaid-zoom__stage");

    overlay.addEventListener("click", function (e) {
      var action = e.target.getAttribute && e.target.getAttribute("data-zoom");
      var box = overlay.getBoundingClientRect();
      if (action === "in") zoomAt(1.25, box.width / 2, box.height / 2);
      else if (action === "out") zoomAt(0.8, box.width / 2, box.height / 2);
      else if (action === "reset") fit();
      else if (action === "close") close();
    });

    overlay.addEventListener("wheel", function (e) {
      e.preventDefault();
      var box = overlay.getBoundingClientRect();
      zoomAt(e.deltaY < 0 ? 1.15 : 1 / 1.15, e.clientX - box.left, e.clientY - box.top);
    }, { passive: false });

    var drag = null;
    stage.addEventListener("pointerdown", function (e) {
      drag = { px: e.clientX, py: e.clientY, x: x, y: y };
      stage.setPointerCapture(e.pointerId);
    });
    stage.addEventListener("pointermove", function (e) {
      if (!drag) return;
      x = drag.x + e.clientX - drag.px;
      y = drag.y + e.clientY - drag.py;
      apply();
    });
    stage.addEventListener("pointerup", function () { drag = null; });
    stage.addEventListener("dblclick", fit);

    document.addEventListener("keydown", function (e) {
      if (overlay.hidden) return;
      if (e.key === "Escape") close();
      else if (e.key === "+" || e.key === "=") zoomAt(1.25, overlay.clientWidth / 2, overlay.clientHeight / 2);
      else if (e.key === "-") zoomAt(0.8, overlay.clientWidth / 2, overlay.clientHeight / 2);
      else if (e.key === "0") fit();
    });
  }

  function open(diagram) {
    if (!overlay) build();
    overlay.querySelector(".mermaid-zoom__help").textContent = label("help");
    overlay.querySelector('[data-zoom="reset"]').textContent = label("reset");
    overlay.querySelector('[data-zoom="close"]').textContent = label("close");
    // Keep the size of the diagram in the page while it is in the overlay
    placeholder = document.createElement("div");
    placeholder.style.height = diagram.offsetHeight + "px";
    current = diagram;
    current.style.width = diagram.offsetWidth + "px";
    diagram.parentNode.replaceChild(placeholder, diagram);
    stage.appendChild(diagram);
    overlay.hidden = false;
    document.documentElement.style.overflow = "hidden";
    fit();
    overlay.querySelector('[data-zoom="close"]').focus();
  }

  function close() {
    if (!current) return;
    current.style.width = "";
    placeholder.parentNode.replaceChild(current, placeholder);
    current.focus();
    current = placeholder = null;
    overlay.hidden = true;
    document.documentElement.style.overflow = "";
  }

  // The theme replaces each <pre class="mermaid"> by a <div class="mermaid"> once Mermaid is
  // loaded: the rendered diagrams are marked as they appear, the clicks are delegated.
  function mark() {
    document.querySelectorAll("div.mermaid:not([data-zoom-ready])").forEach(function (diagram) {
      diagram.setAttribute("data-zoom-ready", "");
      diagram.setAttribute("tabindex", "0");
      diagram.setAttribute("role", "button");
      diagram.setAttribute("title", label("open"));
      diagram.setAttribute("aria-label", label("open"));
    });
  }

  function diagramOf(e) {
    var diagram = e.target.closest && e.target.closest("div.mermaid[data-zoom-ready]");
    return diagram && !current ? diagram : null;
  }

  document.addEventListener("click", function (e) {
    var diagram = diagramOf(e);
    if (diagram) open(diagram);
  });
  document.addEventListener("keydown", function (e) {
    var diagram = diagramOf(e);
    if (diagram && (e.key === "Enter" || e.key === " ")) {
      e.preventDefault();
      open(diagram);
    }
  });

  new MutationObserver(mark).observe(document.documentElement, { childList: true, subtree: true });
  mark();
})();
