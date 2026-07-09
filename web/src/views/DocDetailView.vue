<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useBemm } from 'bemm'
import MarkdownContent from '@/components/MarkdownContent.vue'
import SiteLayout from '@/components/SiteLayout.vue'
import docsData from '@/generated/docs.json'

const bemm = useBemm('page', { return: 'string' })

const route = useRoute()

const document = computed(() => {
  const slug = String(route.params.docSlug ?? '')
  return docsData.documents.find((candidate) => candidate.slug === slug)
})
</script>

<template>
  <SiteLayout>
    <main :class="bemm()">
      <template v-if="document">
        <section :class="bemm('intro')">
          <div :class="bemm('container')">
            <p :class="bemm('eyebrow')">Docs</p>
            <h1 :class="bemm('title')">{{ document.title }}</h1>
            <p :class="bemm('subtitle')">{{ document.summary }}</p>
            <div :class="bemm('links')">
              <RouterLink to="/docs/">All docs</RouterLink>
              <a :href="document.sourceUrl" target="_blank" rel="noopener">Open on GitHub</a>
            </div>
          </div>
        </section>

        <section :class="bemm('body')">
          <div :class="bemm('container')">
            <MarkdownContent :html="document.html" />
          </div>
        </section>
      </template>

      <template v-else>
        <section :class="bemm('intro')">
          <div :class="bemm('container')">
            <p :class="bemm('eyebrow')">Docs</p>
            <h1 :class="bemm('title')">Document not found.</h1>
            <p :class="bemm('subtitle')">The requested documentation page is not part of the published docs index.</p>
            <div :class="bemm('links')">
              <RouterLink to="/docs/">All docs</RouterLink>
            </div>
          </div>
        </section>
      </template>
    </main>
  </SiteLayout>
</template>