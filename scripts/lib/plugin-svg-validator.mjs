const MAX_SVG_BYTES = 32 * 1024;
const MAX_SVG_ELEMENTS = 128;
const MAX_SVG_ATTRIBUTES = 512;
const MAX_SVG_REFERENCES = 64;
const MAX_SVG_PATH_DATA_BYTES = 16 * 1024;

const DISALLOWED_ELEMENT_PATTERN = /<(?:script|foreignObject|iframe|object|embed|audio|video|canvas|image|animate|animateMotion|animateTransform|set|mpath|feImage)\b/i;
const DISALLOWED_MISC_PATTERN = /<!DOCTYPE|<!ENTITY|<\?xml-stylesheet|<html\b|<body\b/i;
const EVENT_HANDLER_PATTERN = /\son[a-z][a-z0-9_-]*\s*=/i;
const STYLE_TAG_PATTERN = /<style\b/i;
const STYLE_ATTRIBUTE_PATTERN = /\sstyle\s*=/i;
const EXTERNAL_REFERENCE_PATTERN = /\b(?:href|xlink:href)\s*=\s*(['"])\s*(?!#)[^'"]+\1/i;
const REMOTE_RESOURCE_ATTRIBUTE_PATTERN = /\b(?:src|poster|data|from|to)\s*=\s*(['"])\s*(?:https?:|data:|javascript:|mailto:|ftp:|\/\/)[^'"]*\1/i;
const URL_FUNCTION_PATTERN = /url\(\s*(['"]?)(.*?)\1\s*\)/gi;
const TAG_PATTERN = /<([A-Za-z][A-Za-z0-9:_-]*)(\s[^<>]*?)?>/g;
const ATTRIBUTE_PATTERN = /([A-Za-z_:][A-Za-z0-9:._-]*)\s*=\s*(['"])(.*?)\2/g;
const ID_PATTERN = /\bid\s*=\s*(['"])(.*?)\1/gi;
const HREF_PATTERN = /\b(?:href|xlink:href)\s*=\s*(['"])(.*?)\1/gi;
const PATH_DATA_PATTERN = /\bd\s*=\s*(['"])(.*?)\1/gi;

function normalizeElementName(name) {
  const normalized = name.includes(":") ? name.split(":").pop() : name;
  return normalized?.toLowerCase() ?? "";
}

function collectMatches(pattern, value, transform) {
  const matches = [];
  for (const match of value.matchAll(pattern)) {
    matches.push(transform(match));
  }
  return matches;
}

function validateReferenceValue(reference, sourceName) {
  const normalized = reference.trim();
  if (normalized === "") {
    throw new Error(`${sourceName}: icon.svg contains an empty SVG reference.`);
  }
  if (normalized.startsWith("#") === false) {
    throw new Error(`${sourceName}: icon.svg may only reference internal SVG fragments.`);
  }
  return normalized.slice(1);
}

export function validatePluginSVG(svgText, sourceName = "icon.svg") {
  if (typeof svgText !== "string") {
    throw new Error(`${sourceName}: icon.svg must be UTF-8 text.`);
  }

  const trimmed = svgText.trim();
  if (trimmed.startsWith("<svg") === false) {
    throw new Error(`${sourceName}: icon.svg must be an SVG document.`);
  }

  const byteLength = Buffer.byteLength(svgText, "utf8");
  if (byteLength > MAX_SVG_BYTES) {
    throw new Error(`${sourceName}: icon.svg must be 32 KiB or smaller.`);
  }

  if (DISALLOWED_ELEMENT_PATTERN.test(svgText)) {
    throw new Error(`${sourceName}: icon.svg contains a disallowed SVG element.`);
  }
  if (DISALLOWED_MISC_PATTERN.test(svgText)) {
    throw new Error(`${sourceName}: icon.svg contains unsupported XML or embedded HTML markup.`);
  }
  if (EVENT_HANDLER_PATTERN.test(svgText)) {
    throw new Error(`${sourceName}: icon.svg must not contain event-handler attributes.`);
  }
  if (STYLE_TAG_PATTERN.test(svgText) || STYLE_ATTRIBUTE_PATTERN.test(svgText)) {
    throw new Error(`${sourceName}: icon.svg must not contain style elements or inline style attributes.`);
  }
  if (EXTERNAL_REFERENCE_PATTERN.test(svgText) || REMOTE_RESOURCE_ATTRIBUTE_PATTERN.test(svgText)) {
    throw new Error(`${sourceName}: icon.svg must not contain remote or executable URL references.`);
  }

  const tags = collectMatches(TAG_PATTERN, svgText, (match) => ({
    name: normalizeElementName(match[1]),
    attributes: match[2] ?? ""
  })).filter((tag) => tag.name !== "svg" || tag.attributes.includes("/") === false);
  if (tags.length > MAX_SVG_ELEMENTS) {
    throw new Error(`${sourceName}: icon.svg exceeds the maximum element count of ${MAX_SVG_ELEMENTS}.`);
  }

  const ids = new Set(collectMatches(ID_PATTERN, svgText, (match) => match[2].trim()).filter(Boolean));
  const references = [];
  for (const match of svgText.matchAll(HREF_PATTERN)) {
    references.push(validateReferenceValue(match[2], sourceName));
  }
  for (const match of svgText.matchAll(URL_FUNCTION_PATTERN)) {
    references.push(validateReferenceValue(match[2], sourceName));
  }
  if (references.length > MAX_SVG_REFERENCES) {
    throw new Error(`${sourceName}: icon.svg exceeds the maximum reference count of ${MAX_SVG_REFERENCES}.`);
  }
  for (const reference of references) {
    if (ids.has(reference) === false) {
      throw new Error(`${sourceName}: icon.svg references missing internal fragment #${reference}.`);
    }
  }

  let attributeCount = 0;
  for (const [, name, , value] of svgText.matchAll(ATTRIBUTE_PATTERN)) {
    attributeCount += 1;
    const normalizedName = name.toLowerCase();
    if (normalizedName === "style") {
      throw new Error(`${sourceName}: icon.svg must not contain inline style attributes.`);
    }
    if ((normalizedName === "href" || normalizedName === "xlink:href") && value.trim().startsWith("#") === false) {
      throw new Error(`${sourceName}: icon.svg may only use internal fragment references.`);
    }
  }
  if (attributeCount > MAX_SVG_ATTRIBUTES) {
    throw new Error(`${sourceName}: icon.svg exceeds the maximum attribute count of ${MAX_SVG_ATTRIBUTES}.`);
  }

  const pathDataBytes = collectMatches(PATH_DATA_PATTERN, svgText, (match) => Buffer.byteLength(match[2], "utf8"))
    .reduce((sum, value) => sum + value, 0);
  if (pathDataBytes > MAX_SVG_PATH_DATA_BYTES) {
    throw new Error(`${sourceName}: icon.svg exceeds the maximum path-data budget.`);
  }

  return trimmed;
}
