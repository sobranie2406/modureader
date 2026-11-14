var word = typeof input.selection === "string" ? input.selection.trim() : "";
var settings = input.settings || {};
var candidates = [];
function add(value) {
  if (typeof value !== "string") return;
  value = value.trim();
  if (value && value !== word && value.length <= 256 &&
      !/[\x00-\x1f\x7f]/.test(value) && candidates.indexOf(value) < 0 && candidates.length < 12) {
    candidates.push(value);
  }
}
if (!word || word.length > 256) return {candidates: []};
var rules = [];
try { rules = JSON.parse(typeof settings.rules === "string" ? settings.rules : "[]"); } catch (_) {}
if (Array.isArray(rules)) rules.slice(0, 32).forEach(function (rule) {
  if (!rule || typeof rule.pattern !== "string" || rule.pattern.length > 256 ||
      typeof rule.replacement !== "string" || rule.replacement.length > 256) return;
  var flags = rule.flags === undefined ? "" : rule.flags;
  if (typeof flags !== "string" || !/^[gimsu]*$/.test(flags)) return;
  try { add(word.replace(new RegExp(rule.pattern, flags), rule.replacement)); } catch (_) {}
});
if (settings.french !== false) {
  var elision = /^(?:[cdjlmnst]|qu)['’]([^\s'’]+)$/i.exec(word);
  if (elision) add(elision[1]);
}
if (settings.english !== false && /^[a-z]+$/i.test(word)) {
  if (/ies$/i.test(word) && word.length > 4) add(word.slice(0, -3) + "y");
  if (/s$/i.test(word) && !/(?:ss|us|is)$/i.test(word) && word.length > 3) {
    add(word.slice(0, -1));
    if (/es$/i.test(word)) add(word.slice(0, -2));
    if (/ves$/i.test(word)) { add(word.slice(0, -3) + "f"); add(word.slice(0, -3) + "fe"); }
  }
  function fromEnding(length) {
    var stem = word.slice(0, -length);
    if (stem.length < 2) return;
    if (/([b-df-hj-np-tv-z])\1$/i.test(stem)) add(stem.slice(0, -1));
    add(stem + "e");
    add(stem);
  }
  if (/ied$/i.test(word) && word.length > 4) add(word.slice(0, -3) + "y");
  if (/ed$/i.test(word)) fromEnding(2);
  if (/ying$/i.test(word) && word.length <= 6) add(word.slice(0, -4) + "ie");
  if (/ing$/i.test(word)) fromEnding(3);
  if (/ier$/i.test(word)) add(word.slice(0, -3) + "y");
  if (/iest$/i.test(word)) add(word.slice(0, -4) + "y");
  if (/er$/i.test(word)) fromEnding(2);
  if (/est$/i.test(word)) fromEnding(3);
}
return {candidates: candidates};
