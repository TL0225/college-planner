(function () {
  function text(sel, root) {
    var el = (root || document).querySelector(sel);
    return el ? el.textContent.trim() : null;
  }
  function parseDate(str) {
    if (!str) return null;
    var d = new Date(str);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }
  var path = location.pathname.toLowerCase();
  var host = location.host.toLowerCase();
  var items = [];

  function pushItem(kind, title, dueAt, courseCode, notes, idSuffix) {
    if (!title) return;
    items.push({
      kind: kind,
      title: title,
      dueAt: dueAt || null,
      courseCode: courseCode || null,
      notes: notes || "",
      lmsItemId: location.href + (idSuffix ? "#" + String(idSuffix).slice(0, 48) : ""),
    });
  }

  // Brightspace / D2L
  if (/\/d2l\/lms\/dropbox\//.test(path) || /assignments\/\d+/.test(path) || /\/assignments\//.test(path)) {
    var title = text(".d2l-page-title") || text("h1") || document.title;
    var dueEl = document.querySelector(
      ".d2l-dates-instrument, [data-due-date], .due_date_display, time[datetime]",
    );
    var dueDate = dueEl
      ? parseDate(
          dueEl.getAttribute("data-value") ||
            dueEl.getAttribute("datetime") ||
            dueEl.textContent,
        )
      : null;
    pushItem(
      "assignment",
      title || "Assignment",
      dueDate,
      text(".d2l-navigation-slink") || text(".course-title"),
      text(".d2l-editor, .user_content, .description") || "",
    );
  } else if (/\/d2l\/le\/news\//.test(path) || /announcements/.test(path)) {
    document.querySelectorAll(".d2l-news-item, article, .announcement").forEach(function (node) {
      var t = text("h2, h3, .title", node) || text("a", node);
      pushItem("announcement", t, null, null, text("p, .content", node) || "", t);
    });
  }

  // Canvas
  if (/instructure\.com/.test(host) || /canvas\./.test(host)) {
    document
      .querySelectorAll(".ig-list .ig-row, .assignment, .discussion-topic, .student-assignment")
      .forEach(function (node) {
        var t = text(".ig-title, .assignment-title, h2, a", node);
        if (!t) return;
        var due = text(".due-date, .date-due, .assignment-date", node);
        pushItem(
          "assignment",
          t,
          parseDate(due),
          text("#breadcrumbs li:last-child, .course-title"),
          "",
          t,
        );
      });
    if (!items.length) {
      var pageTitle = text("#assignment_show .title, h1.title") || document.title;
      if (pageTitle) {
        pushItem(
          "assignment",
          pageTitle,
          parseDate(text(".due_date, .date-due")),
          text("#breadcrumbs li:nth-child(2)"),
          text(".description, .user_content") || "",
        );
      }
    }
  }

  // Blackboard
  if (/blackboard/.test(host) || /\/webapps\//.test(path) || /bb/.test(host)) {
    document
      .querySelectorAll(
        "#content_listContainer li, .contentList > li, .item, .clearfix, .grade-item",
      )
      .forEach(function (node) {
        var t = text("a, h3, .itemHeader, .js-contentTitle", node);
        if (!t || t.length < 2) return;
        var due = text(".dueDate, .date, time", node);
        pushItem(
          /announce/i.test(t) ? "announcement" : "assignment",
          t,
          parseDate(due),
          text("#courseMenuPalette_title, .courseName"),
          text(".vtbegenerated, .contentBox", node) || "",
          t,
        );
      });
  }

  // Moodle
  if (/moodle/.test(host) || /\/mod\/assign\//.test(path) || /\/course\/view\.php/.test(path)) {
    document
      .querySelectorAll(".activityassign, .activity, .assignment, li.activity")
      .forEach(function (node) {
        var t = text(".instancename, a, .activityname", node);
        if (!t) return;
        pushItem(
          "assignment",
          t.replace(/\s+/g, " ").trim(),
          parseDate(text(".date, time, .duedate", node)),
          text(".page-header-headings h1, .coursename"),
          "",
          t,
        );
      });
    if (/\/mod\/assign\//.test(path) && !items.length) {
      pushItem(
        "assignment",
        text("h2, h3, .page-header-headings") || document.title,
        parseDate(text(".duedate, time")),
        text(".page-header-headings h1"),
        text(".activity-description, #intro") || "",
      );
    }
  }

  // Generic fallback: dated links that look like assignments
  if (!items.length) {
    document.querySelectorAll("a[href*='assign'], a[href*='dropbox'], a[href*='homework']").forEach(
      function (a) {
        var t = (a.textContent || "").trim();
        if (t.length > 3 && t.length < 160) pushItem("assignment", t, null, null, "", t);
      },
    );
  }

  return JSON.stringify({ pageType: path, items: items.slice(0, 40) });
})();
