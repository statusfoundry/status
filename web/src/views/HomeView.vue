<script setup lang="ts">
import { Badge, Button } from '@sil/ui'
import { useBemm } from 'bemm'

import SignalPanel from '../components/SignalPanel.vue'

const bemm = useBemm('home-view', { return: 'string' })

const pillars = [
  {
    title: 'Native first',
    body: 'A real macOS and iOS app with shared core logic and platform-native views.',
  },
  {
    title: 'Event-based',
    body: 'Triggers, jobs, events, rules, actions, notifications, and audit logs follow one explainable pipeline.',
  },
  {
    title: 'Plugin-powered',
    body: 'Declarative adapters normalize tools into common resources, events, metrics, and actions.',
  },
]
</script>

<template>
  <main :class="bemm()">
    <section :class="bemm('hero')">
      <div :class="bemm('copy')">
        <Badge variant="outline">Status</Badge>
        <h1>A native status layer for everything you run.</h1>
        <p :class="bemm('lede')">
          Connect your tools. See what changed. Act only when needed.
        </p>
        <div :class="bemm('actions')">
          <Button href="/plugins/" variant="primary">Browse plugins</Button>
          <Button href="/docs/" variant="outline">Read docs</Button>
        </div>
      </div>
      <SignalPanel />
    </section>

    <section :class="bemm('grid')" aria-label="Product principles">
      <article v-for="pillar in pillars" :key="pillar.title" :class="bemm('card')">
        <h2>{{ pillar.title }}</h2>
        <p>{{ pillar.body }}</p>
      </article>
    </section>
  </main>
</template>
