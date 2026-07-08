# Mock Operations Plugin

This example is a starter package for third-party plugin authors. It is validated by `npm run plugins:check` but is not published to the hosted registry or bundled into the native apps.

It demonstrates:

- declared network permissions and domains;
- native setup fields;
- one request definition;
- resource, event, and metric mappings;
- manual and cron triggers;
- suggested rules that install disabled;
- app-owned view descriptors;
- review-required action declarations.

The request points at `https://example.com/status.json` as a fixture-shaped endpoint. Replace it with a real HTTPS API and recorded fixtures when adapting this template.
