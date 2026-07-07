<script setup lang="ts">
import { Badge, Card } from '@sil/ui'
import { useBemm } from 'bemm'

import docsData from '../generated/docs.json'

const bemm = useBemm('docs-view', { return: 'string' })
const documents = docsData.documents
</script>

<template>
  <main :class="bemm()">
    <section :class="bemm('intro')">
      <Badge variant="outline">Docs</Badge>
      <h1>Product doctrine and implementation contracts.</h1>
      <p>
        Status is documentation-led. These documents define the native app, plugin model, registry,
        automation boundaries, security posture, and validation expectations.
      </p>
    </section>

    <section :class="bemm('list')" aria-label="Documentation">
      <Card v-for="document in documents" :key="document.path" :title="document.title" :class="bemm('item')">
        <p>{{ document.summary }}</p>
        <a :href="document.path">Open source document</a>
      </Card>
    </section>
  </main>
</template>
