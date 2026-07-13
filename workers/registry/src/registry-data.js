export const registry = {
  "schemaVersion": "1.0.0",
  "plugins": [
    {
      "id": "com.status.appstoreconnect",
      "name": "App Store Connect",
      "summary": "Track app review, builds, and release status.",
      "description": "Read-only App Store Connect status events for apps, review state, build processing, and release readiness.",
      "category": "developer",
      "icon": "sf:app.badge",
      "iconSvg": "<svg fill=\"currentColor\" role=\"img\" viewBox=\"0 0 24 24\" xmlns=\"http://www.w3.org/2000/svg\" aria-label=\"App Store\">\n  <title>App Store</title>\n  <path d=\"M8.8086 14.9194l6.1107-11.0368c.0837-.1513.1682-.302.2437-.4584.0685-.142.1267-.2854.1646-.4403.0803-.3259.0588-.6656-.066-.9767-.1238-.3095-.3417-.5678-.6201-.7355a1.4175 1.4175 0 0 0-.921-.1924c-.3207.043-.6135.1935-.8443.4288-.1094.1118-.1996.2361-.2832.369-.092.1463-.175.2979-.259.4492l-.3864.6979-.3865-.6979c-.0837-.1515-.1667-.303-.2587-.4492-.0837-.1329-.1739-.2572-.2835-.369-.2305-.2353-.5233-.3857-.844-.429a1.4181 1.4181 0 0 0-.921.1926c-.2784.1677-.4964.426-.6203.7355-.1246.311-.1461.6508-.066.9767.038.155.0962.2984.1648.4403.0753.1564.1598.307.2437.4584l1.248 2.2543-4.8625 8.7825H2.0295c-.1676 0-.3351-.0007-.5026.0092-.1522.009-.3004.0284-.448.0714-.3108.0906-.5822.2798-.7783.548-.195.2665-.3006.5929-.3006.9279 0 .3352.1057.6612.3006.9277.196.2683.4675.4575.7782.548.1477.043.296.0623.4481.0715.1675.01.335.009.5026.009h13.0974c.0171-.0357.059-.1294.1-.2697.415-1.4151-.6156-2.843-2.0347-2.843zM3.113 18.5418l-.7922 1.5008c-.0818.1553-.1644.31-.2384.4705-.067.1458-.124.293-.1611.452-.0785.3346-.0576.6834.0645 1.0029.1212.3175.3346.583.607.7549.2727.172.5891.2416.9013.1975.3139-.044.6005-.1986.8263-.4402.1072-.1148.1954-.2424.2772-.3787.0902-.1503.1714-.3059.2535-.4612L6 19.4636c-.0896-.149-.9473-1.4704-2.887-.9218m20.5861-3.0056a1.4707 1.4707 0 0 0-.779-.5407c-.1476-.0425-.2961-.0616-.4483-.0705-.1678-.0099-.3352-.0091-.503-.0091H18.648l-4.3891-7.817c-.6655.7005-.9632 1.485-1.0773 2.1976-.1655 1.0333.0367 2.0934.546 3.0004l5.2741 9.3933c.084.1494.167.299.2591.4435.0837.131.1739.2537.2836.364.231.2323.5238.3809.8449.4232.3192.0424.643-.0244.9217-.1899.2784-.1653.4968-.4204.621-.7257.1246-.3072.146-.6425.0658-.9641-.0381-.1529-.0962-.2945-.165-.4346-.0753-.1543-.1598-.303-.2438-.4524l-1.216-2.1662h1.596c.1677 0 .3351.0009.5029-.009.1522-.009.3007-.028.4483-.0705a1.4707 1.4707 0 0 0 .779-.5407A1.5386 1.5386 0 0 0 24 16.452a1.539 1.539 0 0 0-.3009-.9158Z\"/>\n</svg>",
      "accentColor": "#2F80ED",
      "author": {
        "name": "Status Foundry",
        "publisherId": "status-foundry",
        "websitePath": "/publishers/status-foundry/",
        "externalUrl": "https://github.com/statusfoundry",
        "repositoryUrl": "https://github.com/statusfoundry/status",
        "publisherSummary": "Official Status integrations and reference plugin packages."
      },
      "trustLevel": "official",
      "permissions": [
        "network",
        "keychain",
        "private-key",
        "background-refresh"
      ],
      "domains": [
        "api.appstoreconnect.apple.com"
      ],
      "versions": [
        {
          "version": "0.1.0",
          "minCoreVersion": "0.1.0",
          "platforms": [
            "macOS",
            "iOS"
          ],
          "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.appstoreconnect/0.1.0/com.status.appstoreconnect-0.1.0.statusplugin.zip",
          "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.appstoreconnect/0.1.0/manifest.json",
          "sha256": "e878d53f899f1fab48d75f6892e63e437adcd7c7cc1346f335a3612d6eb492c6",
          "signature": "41dYsGDBvBCYW9KOx+IPiRx9UJkeSgqbajU/e5yg6AJVvKm6aa3q3wlw4kAutm8rTQAfal2h9aJIsOFH3U+LDw==",
          "signedBy": "status-foundry-dev",
          "releasedAt": "2026-07-07T12:00:00Z"
        }
      ]
    },
    {
      "id": "com.status.github",
      "name": "GitHub",
      "summary": "Track workflow failures, pull requests, and issue activity.",
      "description": "Read-only GitHub repository events for workflow failures, pull requests, and issue activity.",
      "category": "developer",
      "icon": "sf:chevron.left.forwardslash.chevron.right",
      "iconSvg": "<svg fill=\"currentColor\" version=\"1.1\" id=\"Layer_1\" xmlns=\"http://www.w3.org/2000/svg\" x=\"0px\" y=\"0px\" viewBox=\"0 0 72 72\" xml:space=\"preserve\" role=\"img\" aria-label=\"GitHub\">\n  <title>GitHub</title>\n  <g>\n    <path d=\"M27.5,54.5c0,0.2,0.3,0.4,0.6,0.4c0.3,0,0.6-0.2,0.6-0.4c0-0.2-0.3-0.4-0.6-0.4S27.5,54.3,27.5,54.5z\"/>\n    <path d=\"M27.1,64.1c0.9,0.2,1.7-0.5,1.7-1.5v-5.4c-1.1,0.2-2.4,0.3-3,0.3c-1.6-0.1-3.1-0.3-3.9-0.8c-0.9-0.5-2.1-1.5-2.5-2.3c-0.5-1.1-0.6-1.7-1.2-2.6c-0.5-0.9-1.5-1.8-2.1-2.1c-0.6-0.3-1.2-0.8-1.3-1.1c-0.1-0.3,0.1-0.7,0.7-0.8c0.6-0.1,1.6,0.1,2.6,0.6c0.8,0.4,1.7,1.4,2.3,2.3c0.7,1.1,1.7,2.1,2.5,2.6c0.8,0.5,2.5,0.7,4.1,0.5c0.6-0.1,1.3-0.3,1.8-0.6c0.2-1.5,0.9-2.8,1.9-3.9c-8.5-1-13.1-5-13.1-13.6c0-3.3,1.1-6.1,3-8.2c-0.2-0.5-0.4-1.1-0.5-1.9c-0.2-1.8,0-2.9,0.3-3.9c0.2-1.1,0.5-1.8,0.5-1.8s1.3-0.1,2.5,0.2c1.1,0.4,2.1,0.7,3.5,1.5c0.7,0.4,1.3,0.8,1.8,1.2c2.2-0.6,4.7-0.9,7.3-0.9c2.6,0,5,0.3,7.2,0.9c0.5-0.3,1.2-0.8,1.8-1.2c1.4-0.8,2.4-1.1,3.5-1.5c1.1-0.4,2.5-0.2,2.5-0.2s0.3,0.7,0.5,1.8c0.2,1.1,0.5,2.1,0.3,3.9c-0.1,0.8-0.3,1.4-0.5,1.9c1.9,2.2,3,4.9,3,8.2c0,8.7-4.7,12.6-13.1,13.6c1.2,1.3,2,3,2,4.9v8.4c0,0.9,0.8,1.6,1.7,1.5c11.6-3.7,19.9-14.6,19.9-27.4C64.8,20.8,51.9,7.9,36,7.9S7.2,20.8,7.2,36.7C7.2,49.5,15.5,60.3,27.1,64.1z\"/>\n    <path d=\"M23,54.4c0,0.2,0.2,0.4,0.5,0.4s0.6-0.1,0.6-0.3c0-0.2-0.2-0.4-0.5-0.4S23,54.2,23,54.4z\"/>\n    <path d=\"M25.3,54.8c0,0.2,0.2,0.4,0.6,0.4c0.3,0,0.6-0.1,0.6-0.3c0-0.2-0.2-0.4-0.6-0.4S25.3,54.6,25.3,54.8z\"/>\n    <path d=\"M21.1,53c-0.1,0.2,0,0.4,0.3,0.6c0.2,0.2,0.5,0.1,0.6,0c0.1-0.2,0-0.4-0.3-0.6C21.5,52.8,21.2,52.8,21.1,53z\"/>\n    <path d=\"M18.7,49.7c-0.1,0.1-0.1,0.4,0.1,0.5c0.2,0.2,0.4,0.2,0.6,0.1c0.1-0.1,0.1-0.4-0.1-0.5C19,49.6,18.8,49.6,18.7,49.7z\"/>\n    <path d=\"M17.4,48.8c-0.1,0.1,0,0.4,0.3,0.5c0.2,0.1,0.5,0.1,0.5-0.1s0-0.4-0.3-0.5C17.7,48.6,17.4,48.6,17.4,48.8z\"/>\n    <path d=\"M19.9,51.3c-0.1,0.1-0.1,0.4,0,0.6c0.2,0.2,0.4,0.3,0.6,0.2c0.1-0.1,0.1-0.4,0-0.6C20.3,51.3,20,51.2,19.9,51.3z\"/>\n  </g>\n</svg>",
      "accentColor": "#4B5563",
      "author": {
        "name": "Status Foundry",
        "publisherId": "status-foundry",
        "websitePath": "/publishers/status-foundry/",
        "externalUrl": "https://github.com/statusfoundry",
        "repositoryUrl": "https://github.com/statusfoundry/status",
        "publisherSummary": "Official Status integrations and reference plugin packages."
      },
      "trustLevel": "official",
      "permissions": [
        "network",
        "keychain",
        "oauth",
        "background-refresh"
      ],
      "domains": [
        "api.github.com",
        "github.com"
      ],
      "versions": [
        {
          "version": "0.1.0",
          "minCoreVersion": "0.1.0",
          "platforms": [
            "macOS",
            "iOS"
          ],
          "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.github/0.1.0/com.status.github-0.1.0.statusplugin.zip",
          "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.github/0.1.0/manifest.json",
          "sha256": "59c868f227b0f285dedd5416f361118d01483d84d080bbff34e6073af8c72cd8",
          "signature": "/IXSpUGmczyO/5dt0AV50N0QRd7wpMiwJD/VV6wYrPpAnZntjtS3Kw45EGHp/dnHWkgnMrr1I82DgQvrQV4vBA==",
          "signedBy": "status-foundry-dev",
          "releasedAt": "2026-07-07T12:00:00Z"
        }
      ]
    },
    {
      "id": "com.status.gitlab",
      "name": "GitLab",
      "summary": "Track GitLab pipelines, merge requests, issues, and project activity.",
      "description": "Read-only GitLab project events for failed pipelines, merge requests, issues, and project activity.",
      "category": "developer",
      "icon": "sf:shippingbox",
      "iconSvg": "<svg fill=\"currentColor\" version=\"1.1\" id=\"Layer_1\" xmlns=\"http://www.w3.org/2000/svg\" x=\"0px\" y=\"0px\" viewBox=\"0 0 256 236\" xml:space=\"preserve\" role=\"img\" aria-label=\"GitLab\">\n  <title>GitLab</title>\n  <path d=\"M255.51,135.16L241.19,91.1L212.82,3.79c-1.46-4.49-7.82-4.49-9.27,0L175.18,91.1h0l0,0H80.97l0,0h0L52.6,3.79c-1.46-4.49-7.82-4.49-9.27,0L14.96,91.1h0l0,0l0,0v0L0.64,135.16c-1.31,4.02,0.12,8.42,3.54,10.9l123.89,90.01l0,0l0,0l0,0l123.89-90.01C255.38,143.58,256.81,139.18,255.51,135.16z\"/>\n</svg>",
      "accentColor": "#FC6D26",
      "author": {
        "name": "Status Foundry",
        "publisherId": "status-foundry",
        "websitePath": "/publishers/status-foundry/",
        "externalUrl": "https://github.com/statusfoundry",
        "repositoryUrl": "https://github.com/statusfoundry/status",
        "publisherSummary": "Official Status integrations and reference plugin packages."
      },
      "trustLevel": "official",
      "permissions": [
        "network",
        "keychain",
        "background-refresh"
      ],
      "domains": [
        "gitlab.com"
      ],
      "versions": [
        {
          "version": "0.1.0",
          "minCoreVersion": "0.1.0",
          "platforms": [
            "macOS",
            "iOS"
          ],
          "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.gitlab/0.1.0/com.status.gitlab-0.1.0.statusplugin.zip",
          "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.gitlab/0.1.0/manifest.json",
          "sha256": "5d6f2abb28d46ea6de92b0f960434ad6a232461a237692c9542cc9e885570d9f",
          "signature": "HL6dpEsM6h3s+bNi7NPS6XDdEwvlI1Ygjv3oFGW5U0TtfukedT4wCMlcvdVquGa8GsiqnkUghW8A1K2FGhTXDA==",
          "signedBy": "status-foundry-dev",
          "releasedAt": "2026-07-09T12:00:00Z"
        }
      ]
    },
    {
      "id": "com.status.googleplay",
      "name": "Google Play",
      "summary": "Track Google Play reviews and low-rating app feedback.",
      "description": "Read-only Google Play Console status for Android app reviews, ratings, and release-facing signals.",
      "category": "developer",
      "icon": "sf:play.square.stack",
      "iconSvg": "<svg fill=\"currentColor\" role=\"img\" viewBox=\"0 0 24 24\" xmlns=\"http://www.w3.org/2000/svg\" aria-label=\"Google Play\">\n  <title>Google Play</title>\n  <path d=\"M22.018 13.298l-3.919 2.218-3.515-3.493 3.543-3.521 3.891 2.202a1.49 1.49 0 0 1 0 2.594zM1.337.924a1.486 1.486 0 0 0-.112.568v21.017c0 .217.045.419.124.6l11.155-11.087L1.337.924zm12.207 10.065l3.258-3.238L3.45.195a1.466 1.466 0 0 0-.946-.179l11.04 10.973zm0 2.067l-11 10.933c.298.036.612-.016.906-.183l13.324-7.54-3.23-3.21z\"/>\n</svg>",
      "accentColor": "#34A853",
      "author": {
        "name": "Status Foundry",
        "publisherId": "status-foundry",
        "websitePath": "/publishers/status-foundry/",
        "externalUrl": "https://github.com/statusfoundry",
        "repositoryUrl": "https://github.com/statusfoundry/status",
        "publisherSummary": "Official Status integrations and reference plugin packages."
      },
      "trustLevel": "official",
      "permissions": [
        "network",
        "keychain",
        "oauth",
        "background-refresh"
      ],
      "domains": [
        "accounts.google.com",
        "oauth2.googleapis.com",
        "androidpublisher.googleapis.com"
      ],
      "versions": [
        {
          "version": "0.1.0",
          "minCoreVersion": "0.1.0",
          "platforms": [
            "macOS",
            "iOS"
          ],
          "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.googleplay/0.1.0/com.status.googleplay-0.1.0.statusplugin.zip",
          "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.googleplay/0.1.0/manifest.json",
          "sha256": "032a1e510ea0b3402c7587b1f151c882615327234df5fdbb721a2665cf37a4a0",
          "signature": "WeL6C6pZEBT32hJJ1KwuKl8XtnCkDVF3TyHQjoWPr1GnoJ5xF74lc7q37HgVymXGNgvFZPSIq14SWJzTQgwgAg==",
          "signedBy": "status-foundry-dev",
          "releasedAt": "2026-07-09T12:00:00Z"
        }
      ]
    },
    {
      "id": "com.status.jira",
      "name": "Jira",
      "summary": "Track Jira project issues and create follow-up issues from Status automations.",
      "description": "Read Jira project issues and create controlled follow-up issues from Status rules.",
      "category": "developer",
      "icon": "sf:checklist",
      "iconSvg": "<svg fill=\"currentColor\" role=\"img\" viewBox=\"0 0 24 24\" xmlns=\"http://www.w3.org/2000/svg\" aria-label=\"Jira\">\n  <title>Jira</title>\n  <path d=\"M11.571 11.513H0a5.218 5.218 0 0 0 5.232 5.215h2.13v2.057A5.215 5.215 0 0 0 12.575 24V12.518a1.005 1.005 0 0 0-1.005-1.005zm5.723-5.756H5.736a5.215 5.215 0 0 0 5.215 5.214h2.129v2.058a5.218 5.218 0 0 0 5.215 5.214V6.758a1.001 1.001 0 0 0-1.001-1.001zM23.013 0H11.455a5.215 5.215 0 0 0 5.215 5.215h2.129v2.057A5.215 5.215 0 0 0 24 12.483V1.005A1.001 1.001 0 0 0 23.013 0Z\"/>\n</svg>",
      "accentColor": "#0C66E4",
      "author": {
        "name": "Status Foundry",
        "publisherId": "status-foundry",
        "websitePath": "/publishers/status-foundry/",
        "externalUrl": "https://github.com/statusfoundry",
        "repositoryUrl": "https://github.com/statusfoundry/status",
        "publisherSummary": "Official Status integrations and reference plugin packages."
      },
      "trustLevel": "official",
      "permissions": [
        "network",
        "keychain",
        "write-actions",
        "user-configured-domains",
        "background-refresh"
      ],
      "domains": [],
      "versions": [
        {
          "version": "0.1.0",
          "minCoreVersion": "0.1.0",
          "platforms": [
            "macOS",
            "iOS"
          ],
          "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.jira/0.1.0/com.status.jira-0.1.0.statusplugin.zip",
          "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.jira/0.1.0/manifest.json",
          "sha256": "ea390fa8303d349ea8a791fd4ff2670f434921cf998cab2dd0708aa4f01534b2",
          "signature": "MeVfX/jPMriIOWCpGt1EXb9bMiJLP4yauNOLlwAuGMS2c7No7ktJ5//ogQmdzfuPZ50N7suCwh6L/YN0V0dWAQ==",
          "signedBy": "status-foundry-dev",
          "releasedAt": "2026-07-09T12:00:00Z"
        }
      ]
    },
    {
      "id": "com.status.website",
      "name": "Website Uptime",
      "summary": "Track website health and response status.",
      "description": "Declarative uptime checks for sites and endpoints the user chooses to track.",
      "category": "monitoring",
      "icon": "sf:globe",
      "iconSvg": "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" role=\"img\" aria-label=\"Website Uptime\">\n  <circle cx=\"12\" cy=\"12\" r=\"10\"/>\n  <path d=\"M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20\"/>\n  <path d=\"M2 12h20\"/>\n</svg>",
      "accentColor": "#16A34A",
      "author": {
        "name": "Status Foundry",
        "publisherId": "status-foundry",
        "websitePath": "/publishers/status-foundry/",
        "externalUrl": "https://github.com/statusfoundry",
        "repositoryUrl": "https://github.com/statusfoundry/status",
        "publisherSummary": "Official Status integrations and reference plugin packages."
      },
      "trustLevel": "official",
      "permissions": [
        "network",
        "user-configured-domains",
        "background-refresh"
      ],
      "domains": [],
      "versions": [
        {
          "version": "0.1.0",
          "minCoreVersion": "0.1.0",
          "platforms": [
            "macOS",
            "iOS"
          ],
          "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.website/0.1.0/com.status.website-0.1.0.statusplugin.zip",
          "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.website/0.1.0/manifest.json",
          "sha256": "628c9f80a24f1df5e11adfe2953ce2c34cc6e07578fe9933fe2c2d6b917221b4",
          "signature": "iY0OeRyaSXAZXRHjFqwjrWi6+j6aEY2gAM6rSFHpYWO4JqbhNLtI8fosHA19BECexXYzZT9DwNXizGFrJNTbCQ==",
          "signedBy": "status-foundry-dev",
          "releasedAt": "2026-07-07T12:00:00Z"
        }
      ]
    },
    {
      "id": "com.status.youtube",
      "name": "YouTube",
      "summary": "Track YouTube channel status, latest uploads, and creator metrics.",
      "description": "Read-only YouTube channel status for creator accounts, latest uploads, subscriber counts, and channel-level signals.",
      "category": "content",
      "icon": "sf:play.rectangle",
      "iconSvg": "<svg fill=\"currentColor\" version=\"1.1\" id=\"Layer_1\" xmlns=\"http://www.w3.org/2000/svg\" x=\"0px\" y=\"0px\" viewBox=\"0 0 72 72\" xml:space=\"preserve\" role=\"img\" aria-label=\"YouTube\">\n  <title>YouTube</title>\n  <path d=\"M63.5,22.1c-0.7-2.5-2.6-4.4-5.1-5.1C54,15.8,36,15.8,36,15.8s-18,0-22.5,1.3c-2.5,0.7-4.4,2.6-5.1,5.1c-1.4,7.9-1.9,20,0,27.7c0.7,2.5,2.6,4.4,5.1,5.1C18,56.2,36,56.2,36,56.2s18,0,22.5-1.2c2.5-0.7,4.4-2.6,5.1-5.1C65,41.9,65.4,29.8,63.5,22.1z M30.2,44.6V27.4L45.2,36L30.2,44.6z\"/>\n</svg>",
      "accentColor": "#FF0033",
      "author": {
        "name": "Status Foundry",
        "publisherId": "status-foundry",
        "websitePath": "/publishers/status-foundry/",
        "externalUrl": "https://github.com/statusfoundry",
        "repositoryUrl": "https://github.com/statusfoundry/status",
        "publisherSummary": "Official Status integrations and reference plugin packages."
      },
      "trustLevel": "official",
      "permissions": [
        "network",
        "keychain",
        "oauth",
        "background-refresh"
      ],
      "domains": [
        "accounts.google.com",
        "oauth2.googleapis.com",
        "www.googleapis.com"
      ],
      "versions": [
        {
          "version": "0.1.0",
          "minCoreVersion": "0.1.0",
          "platforms": [
            "macOS",
            "iOS"
          ],
          "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.youtube/0.1.0/com.status.youtube-0.1.0.statusplugin.zip",
          "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.youtube/0.1.0/manifest.json",
          "sha256": "7ef0b153ab0d08805df402da42f8048dfbc3f52d0247e0ce1366937beb0c8a78",
          "signature": "VK0sYYZlrvIq/IOvAe3+kqZfogSByBniyKtlmBYvwlfU7Y2o1VGM/bmJz8enXwiLzbJKjX/p/bITqqmmmaVKAA==",
          "signedBy": "status-foundry-dev",
          "releasedAt": "2026-07-09T12:00:00Z"
        }
      ]
    }
  ]
};


export const revocations = {
  "schemaVersion": "1.0.0",
  "revokedPlugins": [],
  "revokedVersions": [],
  "revokedHashes": [],
  "revokedSigningKeys": []
};
