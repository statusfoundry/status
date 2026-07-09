<script setup lang="ts">
import { useBemm } from 'bemm'
import SiteLayout from '@/components/SiteLayout.vue'

const bemm = useBemm('page', { return: 'string' })

const readiness = [
  'Native macOS and iOS shells build from the same Swift package.',
  'Plugin packages are declarative, signed, and validated before registry listing.',
  'Local persistence, notification preferences, action audit logs, and runtime status are implemented.',
]

const installSteps = [
  'Use the latest TestFlight or signed beta build when published.',
  'Install official plugins from the Status registry inside the app.',
  'Review permissions before connecting accounts or enabling actions.',
]
</script>

<template>
  <SiteLayout>
    <main :class="bemm()">
      <section :class="bemm('intro')">
        <div :class="bemm('container')">
          <p :class="bemm('eyebrow')">Beta</p>
          <h1 :class="bemm('title')">Native builds first, public binaries next.</h1>
          <p :class="bemm('subtitle')">
            Status is currently prepared as a source-available beta. Public macOS downloads and iOS TestFlight
            links will be added here after signing, notarization, and release review are ready.
          </p>
        </div>
      </section>

      <section :class="bemm('body')">
        <div :class="[bemm('container'), bemm('grid')]">
          <article :class="bemm('card')">
            <h2>Current readiness</h2>
            <ul>
              <li v-for="item in readiness" :key="item">{{ item }}</li>
            </ul>
          </article>
          <article :class="bemm('card')">
            <h2>Install flow</h2>
            <ol>
              <li v-for="step in installSteps" :key="step">{{ step }}</li>
            </ol>
          </article>
        </div>
      </section>
    </main>
  </SiteLayout>
</template>