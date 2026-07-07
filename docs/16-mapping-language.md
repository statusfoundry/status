# Mapping and Expression Language

This document specifies the small declarative language used inside plugin packages, mainly in `mappings.json` and `requests.json`. It covers selectors, conditions, templates, severity mapping, conditional event emission, and pagination.

The language is deliberately tiny. It must be implementable with a hand-written parser and a plain tree walk over decoded JSON. It requires no scripting engine, no regular expression engine, and no dynamic code of any kind.

Related documents:

- `docs/04-plugin-system.md` — where mappings live inside a plugin package;
- `docs/05-events-automation.md` — rule conditions, which share the operator set defined here;
- `docs/17-event-semantics.md` — state-change detection, deduplication, and StatusItem lifecycle (the runtime semantics behind the `changed_to` operators defined below).

## Implementation status

`StatusCore` currently includes `MappingConditionEvaluator`, a small evaluator for single mapping conditions and AND groups over normalized resource state. It supports the plain operators and the transition operators (`changed`, `changed_to`, `changed_from`) against current and previous resource snapshots. It does not yet include the full JSON selector parser, source iteration, shorthand string parser, template rendering, severity mapping, or pagination runtime.

## Design rules

```txt
Selectors read values. Conditions compare values. Templates format values.
Nothing loops, nothing calls functions, nothing touches the network.
```

Evaluation is deterministic: the same payload, prior state, and mapping always produce the same resources, events, and metrics.

## 1. Selectors

Selectors are a small JSONPath subset. A selector reads a value out of a decoded JSON document.

### Supported constructs

```txt
$                     the evaluation root
$.name                dot field access
$.a.b.c               chained dot access
$['name']             bracket field access (single-quoted key)
$['odd key.name']     bracket access for keys containing dots or spaces
$.items[0]            array index (non-negative integer)
$.data[*]             wildcard — allowed only as the tail of a source selector
```

Dot and bracket access may be mixed freely: `$.data[0]['attributes'].name`.

### Not supported

```txt
..                    recursive descent
[?()]                 filter expressions
[0:2]                 slices
[0,1] / ['a','b']     unions
[(expr)]              script expressions
@                     current-node references inside a selector
negative indices
```

A selector containing any unsupported construct is a validation error at plugin install time, not a runtime error.

### Resolution behavior

- A selector resolves to at most one value: a string, number, boolean, null, object, or array.
- If any step is missing (absent key, index out of range, wrong type traversed), the selector resolves to **missing**. Missing is not an error; conditions and templates define how they treat it below.
- Value selectors (everywhere except `source`) must not contain `[*]`. This is enforced at validation time.

### Iteration model: `source` and item-relative selectors

Mappings do not have loops. Instead, each mapping block declares a `source` selector evaluated against the response document root. The `source` selector produces a list of items, and every other selector in that block is evaluated with `$` bound to the current item.

- If `source` ends in `[*]`, each element of the selected array is an item.
- If `source` selects an array without `[*]`, this is a validation error — write the `[*]` explicitly.
- If `source` selects a single object, that object is the only item.
- If `source` is omitted, the default is `$` — the whole document is one item.
- If `source` resolves to missing, the block produces nothing (zero items, no error).

Example against a JSON:API response:

```json
{
  "resources": [
    {
      "source": "$.data[*]",
      "type": "app",
      "id": "$.id",
      "name": "$.attributes.name"
    }
  ]
}
```

Here `$.id` means "the `id` field of the current element of `$.data`". There is no way to reach back out to the document root from inside an item; if a block needs a document-level value, that is a signal to restructure the mapping, not a missing feature.

### Distinguishing selectors from literal strings

In mapping fields that accept either a selector or a literal, a string starting with `$` is a selector; anything else is a literal. A literal string that must start with `$` is not supported in v1.

## 2. Conditions

Conditions appear in `when` clauses of event mappings. The same operator set is used by the rules engine for rule conditions (`docs/05-events-automation.md`); rules compare event fields, mappings compare payload fields.

### Canonical form: JSON objects

A single condition is an object:

```json
{ "path": "$.attributes.appStoreState", "operator": "equals", "value": "REJECTED" }
```

- `path` — a value selector, evaluated against the current item;
- `operator` — one of the operators below;
- `value` — a literal: string, number, boolean, or null. Omitted for `is_empty` / `is_not_empty`.

### Combinators

There is no nested boolean logic. Exactly two combining forms exist:

- An **array of conditions** is a conjunction: every condition must match (AND).
- An object of the form `{ "any": [ ...conditions... ] }` matches when at least one condition in the array matches (OR).

An `any` object may appear as an element of a top-level array, giving AND-of-ORs. An `any` array may contain only plain conditions — no nested `any`. That is the full extent of boolean structure in v1.

```json
"when": [
  { "path": "$.attributes.appStoreState", "operator": "equals", "value": "REJECTED" },
  { "any": [
    { "path": "$.attributes.platform", "operator": "equals", "value": "IOS" },
    { "path": "$.attributes.platform", "operator": "equals", "value": "MAC_OS" }
  ]}
]
```

This keeps parsing trivial: a `when` value is a single condition object, an array of (condition or `any`) objects, or a shorthand string.

### Shorthand string form

For the common single-comparison case, `when` may be a string:

```txt
<selector> <op> <literal>
```

where `<op>` is one of `==`, `!=`, `>`, `<`, mapping to `equals`, `not_equals`, `greater_than`, `less_than`. Literals in the string form are single-quoted strings, bare numbers, `true`, `false`, or `null`.

```json
"when": "$.attributes.appStoreState == 'REJECTED'"
```

All other operators, and any combination of conditions, require the JSON form. The shorthand is sugar; it desugars to exactly one canonical condition object.

### Operators

```txt
equals
not_equals
contains
not_contains
starts_with
ends_with
greater_than
less_than
is_empty
is_not_empty
changed
changed_to
changed_from
```

Semantics:

- `equals` / `not_equals` — strict comparison after type check. A number never equals a string; `null` equals only `null`.
- `contains` / `not_contains` — substring test when the resolved value is a string; membership test when it is an array of scalars. Any other type does not match `contains` (and therefore matches `not_contains`).
- `starts_with` / `ends_with` — string prefix/suffix tests. Non-strings do not match.
- `greater_than` / `less_than` — numeric comparison. If either side is not a number, the condition does not match.
- `is_empty` — matches when the value is missing, `null`, an empty string, or an empty array.
- `is_not_empty` — the negation of `is_empty`.
- `changed`, `changed_to`, `changed_from` — state-transition operators, defined in section 6.

A missing value behaves as follows: it matches `is_empty`, `not_equals`, and `not_contains`; it matches no other operator.

`matches_severity` (listed in `docs/05-events-automation.md`) is a **rule-level operator only**. It compares an event's severity against a threshold and has no meaning inside a mapping, because severity does not exist until the mapping assigns it. It must not appear in `mappings.json`.

Literal types, in both forms:

```txt
string    single-quoted in shorthand, plain JSON string in canonical form
number    JSON number
boolean   true / false
null      null
```

There are no date literals in v1. Timestamps compare as strings, which works for ISO 8601 ordering; anything cleverer is a core-side concern, not a mapping concern.

## 3. Template strings

Templates produce output strings for titles, summaries, action URLs, and action inputs. A template is a plain string containing zero or more `{{...}}` placeholders.

```json
"summary": "{{resource.name}} needs a reviewer reply."
```

### Placeholder syntax

A placeholder is `{{` + a dot path + `}}`. Whitespace inside the braces is ignored. A dot path is one or more identifiers separated by dots — no brackets, no indices, no `$`.

The first segment selects a scope:

```txt
item        fields of the current mapping item (payload-derived)
resource    the normalized resource the item mapped to (id, name, type, declared fields)
event       the event being built (type, title, severity...) — rules and action templates only
account     the account (id, label) — never secrets
trigger     the trigger that started the job (id, type)
```

A path whose first segment is not a scope name is treated as `item.<path>`. So `{{id}}` in a mapping template means `{{item.id}}`. This keeps the short examples in `docs/04-plugin-system.md` valid.

Which scopes are populated depends on where the template runs: mapping templates see `item`, `resource`, `account`, and `trigger`; rule and action templates (`docs/05-events-automation.md`) see `event`, `account`, and `trigger`. Referencing an unpopulated scope resolves to missing.

### Missing values

A placeholder that resolves to missing or `null` renders as an **empty string**. It is not an error and does not abort the mapping. The engine should log a validation-level warning in developer mode so plugin authors notice, but production behavior is silent substitution. Numbers and booleans render in their canonical JSON form; objects and arrays render as empty string with a developer-mode warning — templates are for scalars.

### Escaping

A literal `{{` is written as `\{{`. A literal backslash before a brace is written `\\{{`. No other escape sequences exist; a lone `\` elsewhere is a literal backslash. Literal `}}` outside a placeholder needs no escaping.

### No functions

Templates cannot call functions. There are no filters, formatters, pipes, conditionals, or arithmetic inside `{{...}}`. If a value needs transformation, either the mapping declares it (severity map, below) or the core provides it as an already-formatted field. This is a permanent v1 boundary, not an oversight.

## 4. Events, severity, and conditional emission

An event mapping declares: emit event of type X, for the item's resource, when the condition holds.

```json
{
  "events": [
    {
      "source": "$.data[*]",
      "type": "app.review.rejected",
      "when": { "path": "$.attributes.appStoreState", "operator": "changed_to", "value": "REJECTED" },
      "resourceId": "$.id",
      "title": "App rejected",
      "summary": "{{resource.name}} needs a reviewer reply.",
      "severity": "critical",
      "actionUrl": "https://appstoreconnect.apple.com/apps/{{id}}/appstore"
    }
  ]
}
```

Fields:

- `source` — iteration root, as in section 1;
- `type` — literal event type; must be declared in `events.json`;
- `when` — condition (string shorthand, single object, or array). If omitted, the event is emitted for every item — acceptable only for push payloads that already represent discrete occurrences (webhooks);
- `resourceId` — selector for the resource this event attaches to;
- `title`, `summary` — templates;
- `actionUrl` — template, optional;
- `severity` — static or mapped, below.

Whether an emitted event survives deduplication is decided by the core, per `docs/17-event-semantics.md`. The mapping only states the condition under which emission is attempted.

### Severity

Severity is one of `ok`, `notice`, `warning`, `critical` (`docs/05-events-automation.md`). A mapping sets it one of two ways.

Static:

```json
"severity": "critical"
```

Mapped from a field via a lookup table:

```json
"severity": {
  "path": "$.attributes.appStoreState",
  "map": {
    "REJECTED": "critical",
    "DEVELOPER_REJECTED": "warning",
    "IN_REVIEW": "notice"
  },
  "default": "notice"
}
```

- `path` — value selector against the current item;
- `map` — exact string match of the resolved value against keys;
- `default` — used when the value is missing or unmatched; required.

Every value on the right-hand side must be one of the four severity levels; this is checked at install time. There is no computed severity — no thresholds, no arithmetic. Threshold-style severity ("views down more than 20%") is computed by the core metric engine, which emits its own events; see `docs/13-implementation-plan.md` WP-2.4.

### Metrics

Metric mappings record numeric points. The YouTube metrics in `docs/06-integrations.md` (`views_7d`, `subscribers_28d`, ...) are expressed like this:

```json
{
  "metrics": [
    {
      "source": "$.items[*]",
      "name": "views_28d",
      "resourceId": "$.id",
      "value": "$.statistics.viewCount",
      "unit": "count"
    }
  ]
}
```

- `name` — literal metric name;
- `resourceId` — selector;
- `value` — selector; must resolve to a number, or to a string containing a number, in which case the engine parses it (many APIs return numeric strings — YouTube does). Anything else drops the point with a warning;
- `unit` — literal, optional;
- `timestamp` — selector, optional; defaults to the job's execution time.

Baseline comparison, drop detection, and delta events are core responsibilities, not mapping responsibilities. The mapping only lands points.

## 5. Pagination

Pagination is declared on a request in `requests.json`. Three types exist in v1.

Every pagination definition accepts `maxPages` — a safety limit on total pages fetched per job, default `20`, hard maximum `100` enforced by the engine regardless of what the plugin declares. Hitting the limit ends pagination normally (the pages fetched so far are processed) and writes a warning to the job result.

### `jsonapi-next-link`

The next page URL is read from the response body.

```json
"pagination": {
  "type": "jsonapi-next-link",
  "path": "$.links.next",
  "maxPages": 20
}
```

- `path` — selector into the response, evaluated against the document root; must resolve to a string URL.
- The URL must be on a declared domain, or the job fails.
- Termination: `path` resolves to missing, `null`, or empty string.

### `cursor`

A cursor value from the response is sent back as a query parameter.

```json
"pagination": {
  "type": "cursor",
  "cursorPath": "$.nextPageToken",
  "param": "pageToken",
  "maxPages": 20
}
```

- `cursorPath` — selector for the next cursor in the response.
- `param` — query parameter name the cursor is sent in on the following request.
- The first request is sent without the parameter.
- Termination: `cursorPath` resolves to missing, `null`, or empty string, or the cursor repeats the previous cursor (loop guard).

### `page-number`

A numeric page parameter is incremented.

```json
"pagination": {
  "type": "page-number",
  "param": "page",
  "start": 1,
  "itemsPath": "$.items",
  "maxPages": 20
}
```

- `param` — query parameter carrying the page number.
- `start` — first page number, default `1`.
- `itemsPath` — selector for the page's item array, evaluated against the document root.
- Termination: `itemsPath` resolves to missing or to an empty array.

All pages of a paginated request are concatenated conceptually: mappings run once per page against each page's document, and the results are merged into one job output. Mappings do not know or care about pagination.

## 6. State-change conditions

Polling must not re-emit the same event every cycle. `app.review.rejected` should fire when the state *becomes* `REJECTED`, not on every poll while it is rejected.

The mapping language provides exactly one hook for this: the transition operators.

```txt
changed              the selected value differs from its prior value
changed_to           the value now equals `value` and previously did not
changed_from         the value previously equaled `value` and now does not
```

```json
"when": { "path": "$.attributes.appStoreState", "operator": "changed_to", "value": "REJECTED" }
```

Rules for use:

- Transition operators are valid only in event-mapping `when` clauses. They are invalid in resource mappings, metric mappings, and rule conditions (rules already receive discrete events).
- `path` must be a field that the resource mapping also captures (a declared resource field or `id`/`name`), because prior values are read from stored resource state. Referencing an uncaptured field is an install-time validation error.
- On the first observation of a resource (no prior state), `changed` and `changed_from` do not match; whether `changed_to` matches on first observation is defined in `docs/17-event-semantics.md`, along with snapshot storage, comparison granularity, and the interaction with fingerprint deduplication. This document defines only the syntax; the runtime semantics live there.

All other operators (`equals`, `contains`, ...) evaluate against the current payload only. Mixing is allowed: an AND array may combine a `changed_to` condition with plain conditions on the current payload.

## 7. Non-goals

The following are explicitly out of scope for the mapping language, in v1 and until deliberately revisited:

- **No loops.** Iteration exists only through `source`. There is no nested iteration, no `foreach`, no joins across items.
- **No user-defined functions**, no built-in function calls, no filters or pipes in templates.
- **No arbitrary code.** Nothing in a plugin package is executed as code; everything is data interpreted by the engine.
- **No regular expressions.** String matching is limited to `contains`, `starts_with`, `ends_with`. `matches_severity` is a rule-level operator (section 2), not a pattern matcher and not part of this language.
- **No network or filesystem access from expressions.** Selectors read the response document; templates read the defined scopes; nothing else is reachable. Requests and pagination are the only things that touch the network, and only against declared domains.
- **No arithmetic, no date math, no aggregation.** Baselines, deltas, and thresholds belong to the core metric engine.
- **No document-root escape from items**, no cross-item references, no state other than the prior-resource-state read performed by transition operators.
- **Deterministic evaluation only.** No randomness, no clock access from expressions (timestamps come from the job, not from the language), no environment inspection.

If an integration cannot be expressed, the correct responses are, in order: restructure the request so the payload fits; extend the core object model deliberately; extend this language deliberately with a version bump. Never work around it with cleverness inside a plugin.

## 8. Worked examples

### App Store Connect: apps and rejection events

Request (from `docs/04-plugin-system.md`):

```json
{
  "requests": {
    "list_apps": {
      "method": "GET",
      "url": "https://api.appstoreconnect.apple.com/v1/apps",
      "auth": "default",
      "pagination": {
        "type": "jsonapi-next-link",
        "path": "$.links.next",
        "maxPages": 20
      }
    }
  }
}
```

Mappings, in the final grammar:

```json
{
  "resources": [
    {
      "source": "$.data[*]",
      "type": "app",
      "id": "$.id",
      "name": "$.attributes.name",
      "fields": {
        "bundleId": "$.attributes.bundleId",
        "sku": "$.attributes.sku",
        "appStoreState": "$.attributes.appStoreState"
      },
      "actionUrl": "https://appstoreconnect.apple.com/apps/{{id}}/appstore"
    }
  ],
  "events": [
    {
      "source": "$.data[*]",
      "type": "app.review.rejected",
      "when": { "path": "$.attributes.appStoreState", "operator": "changed_to", "value": "REJECTED" },
      "resourceId": "$.id",
      "title": "App rejected",
      "summary": "{{resource.name}} needs a reviewer reply.",
      "severity": "critical",
      "actionUrl": "https://appstoreconnect.apple.com/apps/{{id}}/appstore"
    },
    {
      "source": "$.data[*]",
      "type": "app.version.ready_for_sale",
      "when": { "path": "$.attributes.appStoreState", "operator": "changed_to", "value": "READY_FOR_SALE" },
      "resourceId": "$.id",
      "title": "App live",
      "summary": "{{resource.name}} is now available on the App Store.",
      "severity": "notice"
    }
  ]
}
```

Note that `appStoreState` is captured as a resource field, which is what permits the `changed_to` conditions. The original `docs/04-plugin-system.md` example used the shorthand `"when": "$.attributes.appStoreState == 'REJECTED'"`; that remains valid syntax but would re-match every poll and rely entirely on fingerprint deduplication. `changed_to` is the preferred form for review-state events.

### YouTube: channel metrics

Against the YouTube Data API `channels?part=snippet,statistics&mine=true` response:

```json
{
  "resources": [
    {
      "source": "$.items[*]",
      "type": "channel",
      "id": "$.id",
      "name": "$.snippet.title",
      "fields": {
        "subscriberCount": "$.statistics.subscriberCount"
      },
      "actionUrl": "https://studio.youtube.com/channel/{{id}}"
    }
  ],
  "metrics": [
    {
      "source": "$.items[*]",
      "name": "views_total",
      "resourceId": "$.id",
      "value": "$.statistics.viewCount",
      "unit": "count"
    },
    {
      "source": "$.items[*]",
      "name": "subscribers",
      "resourceId": "$.id",
      "value": "$.statistics.subscriberCount",
      "unit": "count"
    }
  ]
}
```

The windowed metrics from `docs/06-integrations.md` (`views_7d`, `views_28d`, `watch_time_28d`) come from the YouTube Analytics API with the window in the request; the mapping shape is identical — one metric block per reported column. Drop detection (`youtube.channel.views_dropped`) is not a mapping condition: the mapping lands points, and the core metric engine compares against baseline and emits the event.

### Generic webhook: pass-through event

The generic webhook payload from `docs/05-events-automation.md` maps with no `when` clause, because each push is already one discrete occurrence:

```json
{
  "events": [
    {
      "type": "{{type}}",
      "resourceId": "$.resource",
      "title": "{{title}}",
      "summary": "{{summary}}",
      "severity": {
        "path": "$.severity",
        "map": { "ok": "ok", "notice": "notice", "warning": "warning", "critical": "critical" },
        "default": "notice"
      },
      "actionUrl": "{{url}}"
    }
  ]
}
```

`source` is omitted, so the whole payload is the single item. The severity map doubles as validation: an unknown severity string degrades to `notice` instead of being trusted.

## Acceptance check

Against `docs/04-plugin-system.md`: the resource mapping, event mapping, and `jsonapi-next-link` pagination examples are all expressible (the resource and event examples are reproduced above in final grammar; the original shorthand `when` string remains parseable).

Against `docs/06-integrations.md`: review-state events (ASC), PR/workflow/issue events (GitHub — plain and `changed_to` conditions on captured fields), Jira issue events (same shape), YouTube metrics (above; drop events are core-side by design), Cloudflare deployment events (`changed_to` on deployment status), uptime events (`changed_to` on a captured `status` field of the website resource), and the generic webhook (above) are all expressible.

The grammar consists of: a five-construct selector subset, flat conditions with one `any` level, scalar templates with one escape rule, a string-keyed severity table, three pagination types, and three transition operators. It is implementable without a scripting engine.
