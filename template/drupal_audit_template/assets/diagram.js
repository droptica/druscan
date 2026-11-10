/*
 * DRUSCAN report - shared Mermaid diagram viewer.
 *
 * Used by include files that show a Mermaid diagram (entity structure, menu, user roles).
 * Styles live in assets/report.css (".ds-diagram").
 *
 * How to use in an include file:
 *   1. Load Mermaid and this file:
 *        <script src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.6.1/mermaid.min.js"></script>
 *        <script src="../assets/diagram.js"></script>
 *   2. Put the Mermaid definition as text into an element:
 *        <div class="mermaid" id="my-diagram">graph TD ...</div>
 *   3. After the HTML is on the page call:
 *        DruscanDiagram.enhanceAll();
 *
 * What the viewer does:
 *   - Draws tree diagrams left-to-right ("graph TD/TB" becomes "graph LR"): many items
 *     make the diagram taller (easy to scroll) instead of very wide and unreadable
 *   - Shows the diagram at readable size in a tall, scrollable area
 *   - Toolbar: zoom in, zoom out, fit whole diagram, 100%, taller view
 *   - Drag to move, Ctrl/Cmd + mouse wheel to zoom at the pointer
 *   - Add data-direction="keep" on the element to keep the original direction
 */
(function () {
  'use strict';

  var MIN_SCALE = 0.1;
  var MAX_SCALE = 8;
  var STEP = 1.25;
  var counter = 0;
  var initialized = false;

  function initMermaid() {
    if (initialized || typeof mermaid === 'undefined') {
      return;
    }
    mermaid.initialize({
      startOnLoad: false,
      theme: 'base',
      securityLevel: 'loose',
      flowchart: {
        useMaxWidth: false,
        htmlLabels: true,
        curve: 'basis',
        nodeSpacing: 16,
        rankSpacing: 70,
        padding: 10
      },
      themeVariables: {
        fontFamily: "'DM Sans', -apple-system, 'Segoe UI', sans-serif",
        fontSize: '15px',
        primaryColor: '#eef1f8',
        primaryTextColor: '#030a3d',
        primaryBorderColor: '#d5d8e4',
        lineColor: '#5b6080',
        secondaryColor: '#f7f8fb',
        tertiaryColor: '#ffffff'
      }
    });
    initialized = true;
  }

  // "graph TD" / "graph TB" / "flowchart TD" -> left-to-right
  function toLeftRight(definition) {
    return definition.replace(/^(\s*)(graph|flowchart)\s+(TD|TB)\b/, '$1$2 LR');
  }

  function button(label, title, onClick) {
    var el = document.createElement('button');
    el.type = 'button';
    el.className = 'ds-diagram__btn';
    el.title = title;
    el.setAttribute('aria-label', title);
    el.innerHTML = label;
    el.addEventListener('click', onClick);
    return el;
  }

  function buildViewer(host, svgMarkup) {
    var wrapper = document.createElement('div');
    wrapper.className = 'ds-diagram';

    var toolbar = document.createElement('div');
    toolbar.className = 'ds-diagram__toolbar';

    var hint = document.createElement('span');
    hint.className = 'ds-diagram__hint';
    hint.textContent = 'Drag to move. Ctrl/Cmd + scroll to zoom.';

    var zoomLabel = document.createElement('span');
    zoomLabel.className = 'ds-diagram__zoom';

    var viewport = document.createElement('div');
    viewport.className = 'ds-diagram__viewport';

    var canvas = document.createElement('div');
    canvas.className = 'ds-diagram__canvas';
    canvas.innerHTML = svgMarkup;
    viewport.appendChild(canvas);

    var svg = canvas.querySelector('svg');
    if (!svg) {
      return null;
    }

    // Natural size of the diagram (from viewBox), used for all zoom maths
    var box = svg.viewBox && svg.viewBox.baseVal;
    var naturalWidth = box && box.width ? box.width : (parseFloat(svg.getAttribute('width')) || 800);
    var naturalHeight = box && box.height ? box.height : (parseFloat(svg.getAttribute('height')) || 600);
    svg.removeAttribute('height');
    svg.style.maxWidth = 'none';
    svg.style.display = 'block';

    var scale = 1;

    function applyScale(newScale, anchorX, anchorY) {
      newScale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, newScale));
      // Keep the point under the pointer (or the centre) in place
      var rect = viewport.getBoundingClientRect();
      var ax = anchorX === undefined ? rect.width / 2 : anchorX - rect.left;
      var ay = anchorY === undefined ? rect.height / 2 : anchorY - rect.top;
      var contentX = (viewport.scrollLeft + ax) / scale;
      var contentY = (viewport.scrollTop + ay) / scale;

      scale = newScale;
      svg.style.width = (naturalWidth * scale) + 'px';
      svg.style.height = (naturalHeight * scale) + 'px';
      svg.setAttribute('width', naturalWidth * scale);

      viewport.scrollLeft = contentX * scale - ax;
      viewport.scrollTop = contentY * scale - ay;
      zoomLabel.textContent = Math.round(scale * 100) + '%';
    }

    function fitScale() {
      var availableWidth = viewport.clientWidth - 32;
      var availableHeight = viewport.clientHeight - 32;
      return Math.min(availableWidth / naturalWidth, availableHeight / naturalHeight);
    }

    // First view: readable size. Shrink only as far as needed to fit the width,
    // and never below 60% - a taller or wider diagram can be scrolled.
    function initialScale() {
      var availableWidth = viewport.clientWidth - 32;
      return Math.max(0.6, Math.min(1, availableWidth / naturalWidth));
    }

    toolbar.appendChild(button('<i class="bi bi-zoom-in"></i>', 'Zoom in', function () { applyScale(scale * STEP); }));
    toolbar.appendChild(button('<i class="bi bi-zoom-out"></i>', 'Zoom out', function () { applyScale(scale / STEP); }));
    toolbar.appendChild(button('<i class="bi bi-arrows-angle-contract"></i> Fit', 'Fit the whole diagram', function () {
      applyScale(fitScale());
      viewport.scrollLeft = 0;
      viewport.scrollTop = 0;
    }));
    toolbar.appendChild(button('100%', 'Show at 100%', function () { applyScale(1); }));
    toolbar.appendChild(button('<i class="bi bi-arrows-expand"></i> Taller', 'Make the diagram area taller or shorter', function () {
      wrapper.classList.toggle('ds-diagram--tall');
    }));
    toolbar.appendChild(zoomLabel);
    toolbar.appendChild(hint);

    // Ctrl/Cmd + wheel = zoom at pointer; plain wheel = normal scrolling
    viewport.addEventListener('wheel', function (event) {
      if (!event.ctrlKey && !event.metaKey) {
        return;
      }
      event.preventDefault();
      applyScale(event.deltaY < 0 ? scale * 1.1 : scale / 1.1, event.clientX, event.clientY);
    }, { passive: false });

    // Drag to move
    var dragging = false;
    var startX = 0;
    var startY = 0;
    var startLeft = 0;
    var startTop = 0;
    viewport.addEventListener('mousedown', function (event) {
      if (event.button !== 0) {
        return;
      }
      dragging = true;
      startX = event.clientX;
      startY = event.clientY;
      startLeft = viewport.scrollLeft;
      startTop = viewport.scrollTop;
      viewport.classList.add('is-dragging');
      event.preventDefault();
    });
    window.addEventListener('mousemove', function (event) {
      if (!dragging) {
        return;
      }
      viewport.scrollLeft = startLeft - (event.clientX - startX);
      viewport.scrollTop = startTop - (event.clientY - startY);
    });
    window.addEventListener('mouseup', function () {
      dragging = false;
      viewport.classList.remove('is-dragging');
    });

    wrapper.appendChild(toolbar);
    wrapper.appendChild(viewport);

    // Replace the old diagram block (old zoom buttons included) with the viewer
    var oldBlock = host.closest('.diagram-section, .diagram-container') || host;
    oldBlock.parentNode.replaceChild(wrapper, oldBlock);

    applyScale(initialScale());
    // Start where the tree starts: find the left-most node (the root in a left-to-right
    // tree) and put it in the middle of the height, at the left edge.
    viewport.scrollLeft = 0;
    viewport.scrollTop = 0;
    var nodes = svg.querySelectorAll('g.node');
    var root = null;
    var rootLeft = Infinity;
    for (var i = 0; i < nodes.length; i++) {
      var nodeRect = nodes[i].getBoundingClientRect();
      if (nodeRect.width > 0 && nodeRect.left < rootLeft) {
        rootLeft = nodeRect.left;
        root = nodeRect;
      }
    }
    if (root) {
      var viewRect = viewport.getBoundingClientRect();
      var rootCentre = root.top + root.height / 2 - viewRect.top;
      viewport.scrollTop = Math.max(0, rootCentre - viewport.clientHeight / 2);
    }

    return wrapper;
  }

  function showError(host, message) {
    host.classList.remove('mermaid');
    host.innerHTML = '<div class="alert alert-warning mb-0"><strong>Diagram could not be drawn.</strong> ' + message + '</div>';
  }

  function enhance(host) {
    if (!host || host.getAttribute('data-ds-diagram') === 'done') {
      return;
    }
    host.setAttribute('data-ds-diagram', 'done');

    if (typeof mermaid === 'undefined') {
      showError(host, 'The Mermaid library is not loaded (no internet connection?).');
      return;
    }
    initMermaid();

    var definition = host.textContent || '';
    if (host.getAttribute('data-direction') !== 'keep') {
      definition = toLeftRight(definition);
    }
    if (!definition.trim()) {
      showError(host, 'No diagram data.');
      return;
    }

    counter += 1;
    var renderId = 'ds-diagram-svg-' + counter;

    // Mermaid measures label widths when it draws. The report font must be loaded first,
    // otherwise labels are measured with another font and get cut off.
    waitForFonts().then(function () {
      return mermaid.render(renderId, definition);
    }).then(function (result) {
      var svgMarkup = result && result.svg ? result.svg : result;
      if (!buildViewer(host, svgMarkup)) {
        showError(host, 'Mermaid returned no drawing.');
      }
    }).catch(function (error) {
      showError(host, String(error && error.message ? error.message : error));
    });
  }

  // Resolves when the report font is ready (or after 2.5 seconds, e.g. when offline).
  function waitForFonts() {
    if (!document.fonts || !document.fonts.load) {
      return Promise.resolve();
    }
    var loading = Promise.all([
      document.fonts.load("15px 'DM Sans'"),
      document.fonts.load("bold 15px 'DM Sans'")
    ]).then(function () {
      return document.fonts.ready;
    }).catch(function () {});
    var timeout = new Promise(function (resolve) {
      setTimeout(resolve, 2500);
    });
    return Promise.race([loading, timeout]);
  }

  window.DruscanDiagram = {
    enhance: enhance,
    enhanceAll: function (root) {
      var nodes = (root || document).querySelectorAll('.mermaid');
      for (var i = 0; i < nodes.length; i++) {
        enhance(nodes[i]);
      }
    }
  };
})();
