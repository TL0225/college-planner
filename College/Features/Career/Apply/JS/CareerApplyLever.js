// CareerApplyLever.js
// Feature: Career / Apply / Lever (Tier A)

(function () {
  window.collegeCareerApplyLever = {
    autofill: function (payloadJSON) {
      var payload = JSON.parse(payloadJSON || "{}");
      var mapDef = window.__collegeCareerApplyFieldMap || { fields: [] };
      var map = window.collegeCareerApplyMapResolver.buildFieldMap(payload, mapDef);
      window.collegeCareerApply.fill(payloadJSON, JSON.stringify(map), true);
    },
    attachResume: function (fileName, base64Data, mimeType) {
      return window.collegeCareerApply.attachResume(fileName, base64Data, mimeType);
    }
  };
})();
