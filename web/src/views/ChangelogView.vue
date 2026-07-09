<script setup lang="ts">
import { useBemm } from 'bemm'
import SiteLayout from '@/components/SiteLayout.vue'

const bemm = useBemm('page', { return: 'string' })

const changes = [
  {
    version: '0.1.0',
    date: '2026-07-09',
    items: [
      'Native app shells, shared StatusCore package, local persistence, plugin loading, and event pipeline.',
      'Official declarative plugins for App Store Connect, GitHub, and website uptime.',
      'Cloudflare registry worker, R2 package layout, Pages website, and CI/deploy workflows.',
      'Notification preferences, notification history, provider-backed actions, and audit logging.',
    ],
  },
]
</script>

<template>
  <SiteLayout>
    <main :class="bemm()">
      <section :class="bemm('intro')">
        <div :class="bemm('container')">
          <p :class="bemm('eyebrow')">Changelog</p>
          <h1 :class="bemm('title')">Release notes for Status.</h1>
          <p :class="bemm('subtitle')">
            Public release notes will track app builds, registry changes, plugin updates, and security fixes.
          </p>
        </div>
      </section>

      <section :class="bemm('body')">
        <div :class="[bemm('container'), bemm('list')]">
          <article v-for="change in changes" :key="change.version" :class="bemm('card')">
            <h2>{{ change.version }}</h2>
            <p>{{ change.date }}</p>
            <ul>
              <li v-for="item in change.items" :key="item">{{ item }}</li>
            </ul>
          </article>
        </div>
      </section>
    </main>
  </SiteLayout>
</template>