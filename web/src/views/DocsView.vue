<script setup lang="ts">
import { useBemm } from 'bemm'
import SiteLayout from '@/components/SiteLayout.vue'
import docsData from '@/generated/docs.json'

const bemm = useBemm('page', { return: 'string' })
const docsCardBemm = useBemm('docs-card', { return: 'string' })

const documents = docsData.documents
</script>

<template>
  <SiteLayout>
    <main :class="bemm()">
      <section :class="bemm('intro')">
        <div :class="bemm('container')">
          <p :class="bemm('eyebrow')">Docs</p>
          <h1 :class="bemm('title')">Product doctrine and implementation contracts.</h1>
          <p :class="bemm('subtitle')">
            Status is documentation-led. These documents define the native app, plugin model, registry,
            automation boundaries, security posture, and validation expectations.
          </p>
        </div>
      </section>

      <section :class="bemm('body')">
        <div :class="[bemm('container'), bemm('list')]">
          <article
            v-for="document in documents"
            :key="document.slug"
            :class="[bemm('card'), docsCardBemm()]"
          >
            <h2>{{ document.title }}</h2>
            <p>{{ document.summary }}</p>
            <RouterLink :to="document.path">Read document</RouterLink>
          </article>
        </div>
      </section>
    </main>
  </SiteLayout>
</template>

<style lang="scss">
.docs-card {
  min-height: 180px;

  a {
    display: inline-flex;
    margin-top: var(--space-m);
    font-weight: var(--font-weight-semibold);
  }
}

.page__list {
  grid-template-columns: repeat(2, minmax(0, 1fr));

  @media (max-width: 820px) {
    grid-template-columns: 1fr;
  }
}
</style>