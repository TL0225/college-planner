// CareerApplyJSBridge.js
// Feature: Career / Apply
// Purpose: Base apply bridge — inventory, fill, read-back verify, shadow DOM traversal.

(function () {
  if (window.__collegeCareerApplyBridge) return;
  window.__collegeCareerApplyBridge = true;

  const STABILIZE_MS = 400;
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.careerApply;

  function post(msg) {
    if (handler) handler.postMessage(msg);
  }

  post({ type: "bridgePing", ok: true });

  function deepQueryAll(selector, root, depth, maxDepth) {
    root = root || document;
    depth = depth || 0;
    maxDepth = maxDepth || 4;
    var out = [];
    try {
      root.querySelectorAll(selector).forEach(function (el) { out.push(el); });
      if (depth >= maxDepth) return out;
      root.querySelectorAll("*").forEach(function (el) {
        if (el.shadowRoot) {
          out = out.concat(deepQueryAll(selector, el.shadowRoot, depth + 1, maxDepth));
        }
      });
    } catch (e) {}
    return out;
  }

  function fieldInventory() {
    var inputs = deepQueryAll("input, select, textarea");
    return inputs.map(function (el) {
      var label = el.getAttribute("aria-label") || el.name || el.id || "";
      return {
        automationId: el.getAttribute("data-automation-id") || "",
        label: label,
        type: el.type || el.tagName.toLowerCase(),
        required: el.required || false,
        name: el.name || "",
        id: el.id || ""
      };
    });
  }

  function setFieldValue(el, value) {
    if (el.tagName === "SELECT") {
      var norm = normalize(String(value));
      for (var i = 0; i < el.options.length; i++) {
        var opt = el.options[i];
        if (normalize(opt.text) === norm || normalize(opt.value) === norm) {
          el.selectedIndex = i;
          el.dispatchEvent(new Event("change", { bubbles: true }));
          return;
        }
      }
      return;
    }
    var proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    var setter = Object.getOwnPropertyDescriptor(proto, "value");
    if (setter && setter.set) setter.set.call(el, String(value));
    else el.value = String(value);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    el.dispatchEvent(new Event("blur", { bubbles: true }));
  }

  function reactSetValue(el, value) {
    setFieldValue(el, value);
  }

  function readBack(el) {
    if (el.tagName === "SELECT") return el.options[el.selectedIndex] ? el.options[el.selectedIndex].text : "";
    if (el.type === "checkbox") return el.checked ? "yes" : "no";
    return el.value || "";
  }

  function normalize(s) {
    return (s || "").replace(/\s+/g, " ").trim().toLowerCase();
  }

  function fillMappedFields(payload, map, tierAllowsWrite) {
    if (!tierAllowsWrite) {
      post({ type: "fieldInventory", fields: fieldInventory() });
      return { fields: [], writeAttemptCount: 0 };
    }
    var results = [];
    var writeAttemptCount = 0;
    (map.fields || []).forEach(function (rule) {
      var value = rule.value;
      if (value == null || value === "") {
        results.push({
          payloadKey: rule.payloadKey,
          intended: "",
          filled: null,
          verified: true,
          status: "skipped",
          atsLabel: rule.label || ""
        });
        return;
      }
      var candidates = [];
      deepQueryAll("input, select, textarea").forEach(function (el) {
        var match = false;
        if (rule.automationId && el.getAttribute("data-automation-id") === rule.automationId) match = true;
        if (!match && rule.name && el.name === rule.name) match = true;
        if (!match && rule.label) {
          var lbl = el.getAttribute("aria-label") || "";
          if (normalize(lbl).indexOf(normalize(rule.label)) >= 0) match = true;
        }
        if (match) candidates.push(el);
      });
      if (candidates.length !== 1) {
        results.push({
          payloadKey: rule.payloadKey,
          intended: String(value),
          filled: null,
          verified: true,
          status: "ambiguous",
          atsLabel: rule.label || ""
        });
        return;
      }
      var el = candidates[0];
      if (el.disabled || el.readOnly) {
        results.push({
          payloadKey: rule.payloadKey,
          intended: String(value),
          filled: null,
          verified: true,
          status: "skipped",
          atsLabel: rule.label || ""
        });
        return;
      }
      writeAttemptCount += 1;
      reactSetValue(el, String(value));
      var filled = readBack(el);
      var verified = normalize(filled) === normalize(String(value));
      results.push({
        payloadKey: rule.payloadKey,
        intended: String(value),
        filled: filled,
        verified: verified,
        status: verified ? "filled" : "wrong_value",
        atsLabel: rule.label || ""
      });
    });
    return { fields: results, writeAttemptCount: writeAttemptCount };
  }

  window.collegeCareerApply = {
    inventory: function () {
      var fields = fieldInventory();
      post({ type: "fieldInventory", fields: fields });
      post({ type: "verificationReport", fields: [], writeAttemptCount: 0 });
    },
    fill: function (payloadJSON, mapJSON, tierAllowsWrite) {
      var payload = JSON.parse(payloadJSON || "{}");
      var map = JSON.parse(mapJSON || "{}");
      var out = fillMappedFields(payload, map, tierAllowsWrite !== false);
      post({
        type: "verificationReport",
        fields: out.fields,
        writeAttemptCount: out.writeAttemptCount
      });
    },
    attachResume: function (fileName, base64Data, mimeType) {
      var inputs = deepQueryAll('input[type="file"]');
      if (!inputs.length) {
        post({ type: "resumeAttach", ok: false, reason: "no_file_input" });
        return false;
      }
      var input = inputs[0];
      try {
        var binary = atob(base64Data || "");
        var bytes = new Uint8Array(binary.length);
        for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
        var blob = new Blob([bytes], { type: mimeType || "application/pdf" });
        var file = new File([blob], fileName || "resume.pdf", { type: mimeType || "application/pdf" });
        var dt = new DataTransfer();
        dt.items.add(file);
        input.files = dt.files;
        input.dispatchEvent(new Event("input", { bubbles: true }));
        input.dispatchEvent(new Event("change", { bubbles: true }));
        post({ type: "resumeAttach", ok: true, fileName: fileName || "resume.pdf" });
        return true;
      } catch (e) {
        post({ type: "resumeAttach", ok: false, reason: String(e) });
        return false;
      }
    }
  };
})();
