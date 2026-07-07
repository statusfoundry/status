# Status Doctrine

This document defines the non-negotiable product beliefs for Status.

## One sentence

Status is a native event-based operations hub for people who run many products, accounts, channels, services, and projects.

## What Status is

Status is:

- a native macOS and iOS app;
- a shared event engine;
- a plugin-powered status dashboard;
- an attention layer above existing tools;
- a local-first automation runner;
- a controlled notification system;
- a bridge between source tools and follow-up actions.

## What Status is not

Status is not:

- a replacement for every dashboard;
- a generic BI tool;
- a full Zapier clone;
- a project management app;
- a support inbox;
- a cloud sync product;
- a place where plugins can create arbitrary UI;
- a system where integrations are bundled forever into the main app.

## Core belief

People do not need more dashboards. They need to know what needs attention.

A dashboard asks the user to inspect everything. Status should tell the user what changed, what is stuck, and what is abnormal.

## Product rules

### 1. The app owns the experience

Plugins never render arbitrary views. The app has a fixed set of high-quality native views: overview cards, lists, detail panels, timelines, metric grids, alert lists, setup forms, rule builders, and audit logs.

Plugins may choose which view types apply and provide data for them.

### 2. Plugins are adapters

A plugin is not a mini-app. A plugin defines:

- authentication;
- permissions;
- domains/endpoints;
- requests;
- response mappings;
- emitted events;
- available actions;
- built-in view descriptors;
- suggested rules.

### 3. Everything is an event

Polling, webhooks, manual refreshes, and local checks should all enter the same pipeline:

```txt
Trigger → Job → Event → Rule → Action → Notification → Audit log
```

### 4. Read-only first

Integrations should start read-only. Write actions must be explicit, limited, permissioned, logged, and reversible where possible.

### 5. Notifications are user-owned

Plugins may mark events as important, but plugins do not decide to spam the user. The core notification engine decides, based on user preferences and rules.

### 6. Automations must be explainable

Every rule should answer:

- what triggered it;
- what conditions matched;
- what action ran;
- what data was used;
- whether it succeeded;
- where the result is.

### 7. Native beats universal

The app should feel like a real Mac app and a real iOS app. Shared logic is good. Lowest-common-denominator UI is not.

### 8. Local-first unless cloud is required

The Mac app should be able to run the core dashboard, scheduler, rules, and actions locally. Cloud exists for push/webhook relay, cross-device sync, and optional always-on execution.

### 9. Calm by default

The default state should be quiet. Status should reduce anxiety, not become another noisy notification system.

### 10. Every integration must collapse into common objects

All plugins normalize into:

- Account
- Resource
- Event
- StatusItem
- Metric
- ActionLink
- Rule
- ActionRun
- Notification

If a plugin cannot normalize into this model, the model needs to be extended deliberately, not hacked around.

## Product taste

Status should feel:

- native;
- calm;
- compact;
- structured;
- fast;
- trustworthy;
- boring in the right way;
- useful before it is clever.

It should not feel:

- like a SaaS dashboard ported to Mac;
- like a spreadsheet;
- like a DevOps wallboard;
- like a widget toy;
- like a generic analytics app;
- like another inbox.

## Default product posture

Status should say:

```txt
Connect your tools. See what changed. Act only when needed.
```

Not:

```txt
Replace all your tools. Automate your whole life. Build workflows visually.
```

The second one is too broad. The first one is useful.