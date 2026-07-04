// CareerApplyAuthBridge.js
// Feature: Career / Apply
// Purpose: Apple Passwords / login autocomplete tagging (from LMS pattern).

(function () {
  if (window.__collegeCareerApplyAuthBridge) return;
  window.__collegeCareerApplyAuthBridge = true;

  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.careerApply;

  function post(msg) {
    if (handler) handler.postMessage(msg);
  }

  function tagLoginFields(root) {
    root = root || document;
    var inputs = root.querySelectorAll("input");
    inputs.forEach(function (el) {
      var type = (el.type || "").toLowerCase();
      if (type === "password") {
        var isNew = /sign.?up|register|create.?account/i.test(document.body.innerText || "");
        el.autocomplete = isNew ? "new-password" : "current-password";
        post({ type: "loginFormDetected", host: location.hostname, url: location.href });
      } else if (type === "email") {
        el.autocomplete = "email";
      } else if (type === "text" && /user|email|login/i.test(el.name || el.id || "")) {
        el.autocomplete = "username";
      }
    });
  }

  tagLoginFields();
  new MutationObserver(function () { tagLoginFields(); }).observe(document.documentElement, { childList: true, subtree: true });

  document.addEventListener("submit", function (e) {
    var form = e.target;
    if (!form || !form.querySelector) return;
    var usernameInput = form.querySelector(
      'input[type="text"], input[type="email"], input[name*="user"], input[id*="user"], input[name*="login"], input[id*="login"]'
    );
    var passwordInput = form.querySelector('input[type="password"]');
    if (usernameInput && passwordInput && usernameInput.value) {
      post({
        type: "loginCredentials",
        username: usernameInput.value,
        host: location.hostname
      });
    }
  }, true);
})();
