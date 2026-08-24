(function () {
  function deepQueryAll(selector, root, depth, maxDepth) {
    root = root || document;
    depth = depth || 0;
    maxDepth = maxDepth || 4;
    var out = [];
    try {
      root.querySelectorAll(selector).forEach(function (el) {
        out.push(el);
      });
      if (depth >= maxDepth) return out;
      root.querySelectorAll("*").forEach(function (el) {
        if (el.shadowRoot) {
          out = out.concat(deepQueryAll(selector, el.shadowRoot, depth + 1, maxDepth));
        }
      });
    } catch (e) {}
    return out;
  }

  function normalize(s) {
    return (s || "").replace(/\s+/g, " ").trim().toLowerCase();
  }

  function payloadValue(payload, key) {
    if (!payload || !key) return null;
    var parts = key.split(".");
    var cur = payload;
    for (var i = 0; i < parts.length; i++) {
      if (cur == null) return null;
      cur = cur[parts[i]];
    }
    if (cur == null || cur === "") return null;
    if (typeof cur === "boolean") return cur ? "Yes" : "No";
    return String(cur);
  }

  function buildFieldMap(payload, mapDef) {
    var fields = (mapDef && mapDef.fields) || [];
    return {
      fields: fields.map(function (rule) {
        return {
          payloadKey: rule.payloadKey,
          label: rule.label,
          name: rule.name,
          automationId: rule.automationId,
          value: payloadValue(payload, rule.payloadKey),
        };
      }),
    };
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
    var proto =
      el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    var setter = Object.getOwnPropertyDescriptor(proto, "value");
    if (setter && setter.set) setter.set.call(el, String(value));
    else el.value = String(value);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    el.dispatchEvent(new Event("blur", { bubbles: true }));
  }

  function readBack(el) {
    if (el.tagName === "SELECT")
      return el.options[el.selectedIndex] ? el.options[el.selectedIndex].text : "";
    return el.value || "";
  }

  function fillMappedFields(map) {
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
          atsLabel: rule.label || rule.name || "",
        });
        return;
      }
      var candidates = [];
      deepQueryAll("input, select, textarea").forEach(function (el) {
        var match = false;
        if (rule.automationId && el.getAttribute("data-automation-id") === rule.automationId)
          match = true;
        if (!match && rule.name && el.name === rule.name) match = true;
        if (!match && rule.label) {
          var lbl = el.getAttribute("aria-label") || "";
          if (normalize(lbl).indexOf(normalize(rule.label)) >= 0) match = true;
          var id = el.id || "";
          if (normalize(id).indexOf(normalize(rule.label).replace(/\s+/g, "")) >= 0) match = true;
        }
        if (match) candidates.push(el);
      });
      if (candidates.length !== 1) {
        results.push({
          payloadKey: rule.payloadKey,
          intended: String(value),
          filled: null,
          verified: true,
          status: candidates.length === 0 ? "missing" : "ambiguous",
          atsLabel: rule.label || rule.name || "",
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
          atsLabel: rule.label || rule.name || "",
        });
        return;
      }
      writeAttemptCount += 1;
      setFieldValue(el, String(value));
      var filled = readBack(el);
      var verified = normalize(filled) === normalize(String(value));
      results.push({
        payloadKey: rule.payloadKey,
        intended: String(value),
        filled: filled,
        verified: verified,
        status: verified ? "filled" : "wrong_value",
        atsLabel: rule.label || rule.name || "",
      });
    });
    return { fields: results, writeAttemptCount: writeAttemptCount };
  }

  var payload = window.__collegeApplyPayload || {};
  var mapDef = window.__collegeApplyMapDef || { fields: [] };

  // Tier C (Oracle / Talemetry): inventory visible form fields without writing.
  if (mapDef.step === "inventory") {
    var inv = [];
    deepQueryAll("input, select, textarea").forEach(function (el) {
      var t = (el.type || "").toLowerCase();
      if (t === "hidden" || t === "submit" || t === "button" || t === "image") return;
      inv.push({
        payloadKey: el.name || el.id || el.getAttribute("data-automation-id") || "",
        intended: "",
        filled: null,
        verified: true,
        status: "inventory",
        atsLabel:
          el.getAttribute("aria-label") ||
          el.placeholder ||
          el.name ||
          el.id ||
          t ||
          "field",
      });
    });
    return JSON.stringify({ fields: inv.slice(0, 80), writeAttemptCount: 0 });
  }

  var map = buildFieldMap(payload, mapDef);
  return JSON.stringify(fillMappedFields(map));
})();
