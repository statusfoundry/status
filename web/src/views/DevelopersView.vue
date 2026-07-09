<script setup lang="ts">
import { useBemm } from 'bemm'
import SiteLayout from '@/components/SiteLayout.vue'

const bemm = useBemm('page', { return: 'string' })

const steps = [
  'Create a declarative plugin package.',
  'Add fixtures and schema validation evidence.',
  'Open a pull request for review.',
  'Status signs and publishes approved packages.',
]
</script>

<template>
  <SiteLayout>
    <main :class="bemm()">
      <section :class="bemm('intro')">
        <div :class="bemm('container')">
          <p :class="bemm('eyebrow')">Developers</p>
          <h1 :class="bemm('title')">Declarative plugins only.</h1>
          <p :class="bemm('subtitle')">
            Plugins describe auth, requests, mappings, events, views, and actions. They do not run arbitrary code,
            own UI, or access secrets directly.
          </p>
        </div>
      </section>

      <section :class="bemm('body')">
        <div :class="[bemm('container'), bemm('grid')]">
          <article :class="bemm('card')">
            <h2>Submission path</h2>
            <ol>
              <li v-for="step in steps" :key="step">{{ step }}</li>
            </ol>
          </article>
          <article :class="bemm('card')">
            <h2>V1 restrictions</h2>
            <p>No public upload form, no self-service publishing, and no custom plugin UI.</p>
          </article>
        </div>
      </section>
    </main>
  </SiteLayout>
</template>