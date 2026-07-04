// LMSJSBridge.js
// Brightspace / D2L page scraper for the in-app LMS portal.
// Injected at document-end via WKUserScript.
// Detects page type from URL and extracts structured data, posting it to Swift
// via window.webkit.messageHandlers.pageContext.postMessage(...).
// Also monitors login forms to offer credential saving.

(function () {
    'use strict';

    // ── Page type detection ──────────────────────────────────────────────────
    function detectPageType(path) {
        if (/\/d2l\/home\/(\d+)/.test(path))        return 'courseHome';
        if (/\/d2l\/lms\/dropbox\//.test(path))      return 'assignment';
        if (/\/d2l\/lms\/grades\//.test(path))        return 'grades';
        if (/\/d2l\/le\/news\//.test(path))           return 'announcement';
        if (/\/d2l\/le\/content\//.test(path))        return 'content';
        if (/\/d2l\/lms\/content\//.test(path))       return 'content';
        if (/\/d2l\/home\/?$/.test(path))             return 'dashboard';
        if (/\/d2l\/login/.test(path) ||
            /\/d2l\/auth/.test(path))                 return 'login';
        return 'other';
    }

    // ── Numeric ID from URL ──────────────────────────────────────────────────
    function extractIdFromPath(path) {
        var m = path.match(/\/(\d{5,})/);
        return m ? m[1] : null;
    }

    // ── Safe text helper ─────────────────────────────────────────────────────
    function text(selector, root) {
        var el = (root || document).querySelector(selector);
        return el ? el.textContent.trim() : null;
    }

    function textAll(selector, root) {
        return Array.from((root || document).querySelectorAll(selector))
            .map(function (el) { return el.textContent.trim(); })
            .filter(Boolean);
    }

    // ── Parse date strings loosely ───────────────────────────────────────────
    function parseDate(str) {
        if (!str) return null;
        var d = new Date(str);
        return isNaN(d.getTime()) ? null : d.toISOString();
    }

    // ── Extractors ───────────────────────────────────────────────────────────
    function extractAssignment() {
        var title       = text('.d2l-page-title') || document.title;
        var dueDateEl   = document.querySelector('.d2l-dates-instrument, [data-due-date], .dco-dates-instrument time');
        var dueDate     = dueDateEl ? parseDate(dueDateEl.getAttribute('data-value') || dueDateEl.getAttribute('datetime') || dueDateEl.textContent) : null;
        var description = text('.d2l-editor, .d2l-htmleditor-container, .d2l-richtext-editor');
        var pointsEl    = document.querySelector('.d2l-grade-result-singleitem-numeric, [class*="points"]');
        var points      = pointsEl ? pointsEl.textContent.trim() : null;
        // Extract course ID from URL path: dropbox URLs contain the course's org unit ID
        // e.g. /d2l/lms/dropbox/user/{courseId}/... or just pick the first 5+ digit number
        var courseIdMatch = location.pathname.match(/\/d2l\/lms\/dropbox\/user\/(\d+)/);
        if (!courseIdMatch) courseIdMatch = location.pathname.match(/\/(\d{5,})/);
        var courseCode  = courseIdMatch ? courseIdMatch[1] : null;
        // Try to get a human-readable course prefix from breadcrumb
        var breadcrumb  = document.querySelector('.d2l-navigation-breadcrumb, [data-location]');
        if (breadcrumb) {
            var crumbLinks = breadcrumb.querySelectorAll('a');
            if (crumbLinks.length >= 2) {
                // Second breadcrumb is usually course name (e.g. "CSE 220 - Data Structures")
                courseCode = crumbLinks[1].textContent.trim().split(/\s*[-\u2013\u2014]\s*/)[0].trim() || courseCode;
            }
        }
        return [{
            id: courseCode || extractIdFromPath(location.pathname),
            title: title,
            dueDate: dueDate,
            courseCode: courseCode,
            points: points,
            description: description,
            lmsItemId: location.href
        }];
    }

    function extractGrades() {
        var rows = document.querySelectorAll('.d2l-grades-table-row, tr.d2l-table-row, [data-grade-name]');
        if (!rows.length) rows = document.querySelectorAll('table tr');
        return Array.from(rows).map(function (row) {
            var cells = row.querySelectorAll('td, th');
            if (cells.length < 2) return null;
            return {
                id: null,
                title: cells[0].textContent.trim(),
                letterGrade: cells[cells.length - 1].textContent.trim(),
                percentage: cells.length >= 3 ? cells[cells.length - 2].textContent.trim() : null,
                lmsItemId: location.href + '#' + cells[0].textContent.trim()
            };
        }).filter(Boolean).filter(function (r) { return r.title.length > 0; });
    }

    function extractAnnouncement() {
        var items = document.querySelectorAll('.d2l-news-item, article.news, [role="article"]');
        if (!items.length) {
            return [{
                id: null,
                title: text('.d2l-news-item-title, .d2l-page-title') || document.title,
                dueDate: parseDate(text('.d2l-news-date, time')),
                description: text('.d2l-news-item-body, .d2l-htmleditor-container'),
                lmsItemId: location.href
            }];
        }
        return Array.from(items).map(function (item, i) {
            return {
                id: String(i),
                title: text('.d2l-news-item-title', item) || item.textContent.substring(0, 80).trim(),
                dueDate: parseDate(text('time, .d2l-news-date', item)),
                description: text('p, .d2l-news-item-body', item),
                lmsItemId: location.href + '#item' + i
            };
        });
    }

    function extractCourseHome() {
        return [{
            id: extractIdFromPath(location.pathname),
            title: text('h1, .d2l-page-title') || document.title,
            lmsItemId: location.href
        }];
    }

    function extractFiles() {
        var downloadExts = /\.(pdf|docx?|xlsx?|pptx?|zip|csv|txt|pages|numbers|keynote)(\?.*)?$/i;
        var seen = {};
        var results = [];
        document.querySelectorAll('a[href]').forEach(function (a) {
            var href = a.href;
            if (!href || href.startsWith('javascript:')) return;
            var hasDownloadAttr = a.hasAttribute('download');
            var name = (a.getAttribute('download') || a.textContent.trim() || a.title || '').trim();
            if (!hasDownloadAttr && !downloadExts.test(href)) return;
            if (seen[href]) return;
            seen[href] = true;
            if (!name) {
                // Try to derive name from the URL
                try { name = decodeURIComponent(href.split('/').pop().split('?')[0]) || href; }
                catch (e) { name = href; }
            }
            // Try to get surrounding context (module/folder heading above this link)
            var context = null;
            var parent = a.closest('[class*="module"], [class*="folder"], [class*="topic"], li, td');
            if (parent) {
                var heading = parent.closest('[class*="module"], [class*="unit"]');
                if (heading) context = (heading.querySelector('h2, h3, [class*="title"]') || {}).textContent;
                if (context) context = context.trim();
            }
            var courseIdMatch = location.pathname.match(/\/d2l\/le\/content\/(\d+)/);
            results.push({
                id: null,
                title: name,
                dueDate: null,
                courseCode: courseIdMatch ? courseIdMatch[1] : null,
                points: null,
                description: context || null,
                lmsItemId: href,
                itemType: 'file'
            });
        });
        return results;
    }

    // ── Main extract function ────────────────────────────────────────────────
    window.__lmsExtract = function () {
        var path     = location.pathname;
        var pageType = detectPageType(path);
        var courseId = extractIdFromPath(path);
        var items    = [];

        switch (pageType) {
            case 'assignment':  items = extractAssignment();   break;
            case 'grades':      items = extractGrades();       break;
            case 'announcement': items = extractAnnouncement(); break;
            case 'courseHome':  items = extractCourseHome();   break;
            case 'content':     items = extractFiles();        break;
            default:            break;
        }

        var payload = {
            pageType: pageType,
            courseId: courseId,
            url: location.href,
            items: items
        };

        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pageContext) {
            window.webkit.messageHandlers.pageContext.postMessage(payload);
        }
        return payload;
    };

    // ── Auto-trigger on load ─────────────────────────────────────────────────
    window.__lmsExtract();

    // ── Autofill attribute injection ─────────────────────────────────────────
    // Tags login form inputs with autocomplete attributes so every password
    // manager (iCloud Keychain, 1Password, Bitwarden, etc.) surfaces its
    // autofill popover the moment the user clicks a username or password field.
    var _taggedForms = typeof WeakSet !== 'undefined' ? new WeakSet() : null;
    function _isTagged(el) { return _taggedForms ? _taggedForms.has(el) : el.__bsAfTagged; }
    function _markTagged(el) { if (_taggedForms) _taggedForms.add(el); else el.__bsAfTagged = true; }

    function tagLoginForm(pwInput) {
        if (_isTagged(pwInput)) return;
        _markTagged(pwInput);
        var ac = pwInput.getAttribute('autocomplete');
        if (!ac || ac === 'off' || ac === '') {
            pwInput.setAttribute('autocomplete', 'current-password');
        }
        var form = pwInput.closest('form') || document;
        form.querySelectorAll(
            'input[type="text"], input[type="email"], input[name*="user"], input[id*="user"], input[name*="login"], input[id*="login"]'
        ).forEach(function (txt) {
            var tac = txt.getAttribute('autocomplete');
            if (!tac || tac === 'off' || tac === '') {
                txt.setAttribute('autocomplete', 'username');
            }
        });
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.loginFormDetected) {
            window.webkit.messageHandlers.loginFormDetected.postMessage({ host: location.host });
        }
    }

    function scanForLoginForms() {
        document.querySelectorAll('input[type="password"]').forEach(tagLoginForm);
    }

    // Run immediately and watch for dynamically injected forms (D2L SSO iframes)
    scanForLoginForms();
    var _formObserver = new MutationObserver(function (mutations) {
        var needsScan = mutations.some(function (m) {
            return Array.from(m.addedNodes).some(function (n) {
                return n.nodeType === 1 && (
                    (n.tagName === 'INPUT' && n.type === 'password') ||
                    (typeof n.querySelectorAll === 'function' && n.querySelectorAll('input[type="password"]').length > 0)
                );
            });
        });
        if (needsScan) scanForLoginForms();
    });
    _formObserver.observe(document.documentElement, { childList: true, subtree: true });

    // ── Login credential interception ─────────────────────────────────────────
    document.addEventListener('submit', function (e) {
        var form = e.target;
        var usernameInput = form.querySelector('input[type="text"], input[name*="user"], input[id*="user"]');
        var passwordInput = form.querySelector('input[type="password"]');
        if (usernameInput && passwordInput) {
            var loginPayload = {
                username: usernameInput.value,
                host: location.hostname
            };
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.loginCredentials) {
                window.webkit.messageHandlers.loginCredentials.postMessage(loginPayload);
            }
        }
    }, true);
})();
