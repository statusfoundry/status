<script setup lang="ts">
import { useBemm } from 'bemm'
import SiteLayout from '@/components/SiteLayout.vue'

const bemm = useBemm('page', { return: 'string' })

const privacy = [
  'Status is local-first for v1; operational data is stored on the device by default.',
  'Credentials belong in platform keychain storage and are never exposed to plugin packages.',
  'Plugins declare network domains and permissions before installation.',
  'Write actions require explicit user permission and produce audit log entries.',
]

const security = [
  'Registry packages include immutable hashes and signature metadata.',
  'Official and reviewed plugins are distributed through Cloudflare R2 and the registry API.',
  'Plugin manifests are validated before publishing and again before install.',
  'Dangerous actions such as deletes, billing changes, and automatic submissions are out of v1 scope.',
]
</script>

<template>
  <SiteLayout>
    <main :class="bemm()">
      <section :class="bemm('intro')">
        <div :class="bemm('container')">
          <p :class="bemm('eyebrow')">Privacy and security</p>
          <h1 :class="bemm('title')">Local-first operations with explicit permissions.</h1>
          <p :class="bemm('subtitle')">
            Status treats integrations as declarative data sources. The app owns credentials, UI, notifications,
            automation decisions, and audit output.
          </p>
        </div>
      </section>

      <section :class="bemm('body')">
        <div :class="[bemm('container'), bemm('grid')]">
          <article :class="bemm('card')">
            <h2>Privacy posture</h2>
            <ul>
              <li v-for="item in privacy" :key="item">{{ item }}</li>
            </ul>
          </article>
          <article :class="bemm('card')">
            <h2>Registry safety</h2>
            <ul>
              <li v-for="item in security" :key="item">{{ item }}</li>
            </ul>
          </article>
        </div>
      </section>
    </main>
  </SiteLayout>
</template>