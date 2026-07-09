<script setup lang="ts">
import { useBemm } from 'bemm'
import StatusIcon from '@/components/Icon.vue'
import site from '@/content/site.json'

const bemm = useBemm('status-logo', { return: 'string' })
</script>

<template>
  <span :class="bemm()" :aria-label="site.brand">
    <StatusIcon :class="bemm('icon')" aria-hidden="true" />
    <span :class="bemm('text')">{{ site.brand }}</span>
  </span>
</template>

<style lang="scss">
.status-logo {
  align-items: center;
  color: currentColor;
  display: inline-flex;
  gap: 0.42em;
  line-height: 1;

  &__icon {
    color: var(--status-logo-mark-color, var(--color-accent));
    flex: 0 0 auto;
    font-size: 1.55em;
  }

  &__text {
    color: currentColor;
    font-size: 1em;
    font-weight: var(--font-weight-bold);
    letter-spacing: 0;
  }
}
</style>