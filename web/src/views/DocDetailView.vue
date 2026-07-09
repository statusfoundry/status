<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useBemm } from 'bemm'
import SiteLayout from '@/components/SiteLayout.vue'
import docsData from '@/generated/docs.json'

const bemm = useBemm('page', { return: 'string' })
const articleBemm = useBemm('doc-article', { return: 'string' })

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
            <article :class="articleBemm()">
              <pre>{{ document.content }}</pre>
            </article>
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

<style lang="scss">
.doc-article {
  background: var(--color-surface);
  border: 1px solid var(--color-border-light);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-sm);
  padding: var(--space-l);

  pre {
    margin: 0;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    color: var(--color-text-primary);
    font-family: var(--font-family-monospace, ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace);
    font-size: var(--font-size-sm);
    line-height: var(--line-height-relaxed);
  }
}
</style>