<script setup lang="ts">
import { useBemm } from 'bemm'
import SiteFooter from '@/components/SiteFooter.vue'
import SiteHeader from '@/components/SiteHeader.vue'

const bemm = useBemm('site-layout', { return: 'string' })
</script>

<template>
  <div :class="bemm()">
    <SiteHeader />
    <slot />
    <SiteFooter />
  </div>
</template>

<style lang="scss">
.site-layout {
  min-height: 100vh;
  background: var(--color-bg);
}
</style>