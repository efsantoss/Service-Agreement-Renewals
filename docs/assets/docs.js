/**
 * Shared behavior for the documentation pages:
 *  - numbers the headings inside <main> (h2 -> "1.", h3 -> "1.1")
 *  - builds the Table of Contents from those headings
 *  - wires the "Export to PDF" button to the browser print dialog
 */
(function () {
  "use strict";

  function slugify(text) {
    return text
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "");
  }

  function buildToc() {
    var target = document.getElementById("toc");
    var headings = document.querySelectorAll("main h2, main h3");
    if (!target || headings.length === 0) {
      return;
    }

    var major = 0;
    var minor = 0;
    var rootList = document.createElement("ol");
    var currentSub = null;

    headings.forEach(function (heading) {
      var isMajor = heading.tagName === "H2";
      var number;

      if (isMajor) {
        major += 1;
        minor = 0;
        number = major + ". ";
      } else {
        minor += 1;
        number = major + "." + minor + " ";
      }

      // Use the title without status badges (e.g. "Planned") for the TOC label.
      var clone = heading.cloneNode(true);
      clone.querySelectorAll(".badge").forEach(function (badge) {
        badge.remove();
      });
      var label = number + clone.textContent.trim();

      // Prepend the number as a text node so child elements (badges) stay intact.
      heading.insertBefore(document.createTextNode(number), heading.firstChild);
      heading.id = heading.id || slugify(label);

      var item = document.createElement("li");
      var link = document.createElement("a");
      link.href = "#" + heading.id;
      link.textContent = label;
      item.appendChild(link);

      if (isMajor) {
        item.className = "toc-l1";
        rootList.appendChild(item);
        currentSub = null;
      } else {
        if (!currentSub) {
          currentSub = document.createElement("ol");
          rootList.lastElementChild.appendChild(currentSub);
        }
        item.className = "toc-l2";
        currentSub.appendChild(item);
      }
    });

    target.appendChild(rootList);
  }

  function wireExportButton() {
    var button = document.getElementById("export-pdf");
    if (button) {
      button.addEventListener("click", function () {
        window.print();
      });
    }
  }

  buildToc();
  wireExportButton();
})();
