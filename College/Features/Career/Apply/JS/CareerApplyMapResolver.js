// CareerApplyMapResolver.js
// Feature: Career / Apply
// Purpose: Resolve payload paths from versioned field map JSON definitions.

(function () {
  if (window.collegeCareerApplyMapResolver) return;

  function payloadValue(payload, key) {
    if (!payload || !key) return null;
    var parts = key.split(".");
    var cur = payload;
    for (var i = 0; i < parts.length; i++) {
      if (cur == null) return null;
      cur = cur[parts[i]];
    }
    if (cur === true) return "Yes";
    if (cur === false) return "No";
    if (cur == null || cur === "") return null;
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
          value: payloadValue(payload, rule.payloadKey)
        };
      })
    };
  }

  window.collegeCareerApplyMapResolver = {
    payloadValue: payloadValue,
    buildFieldMap: buildFieldMap
  };
})();
