<script setup lang="ts">
import { useBemm } from 'bemm'
import site from '@/content/site.json'

const bemm = useBemm('status-icon', { return: 'string' })
</script>

<template>
  <svg
    :class="bemm()"
    xmlns="http://www.w3.org/2000/svg"
    viewBox="0 0 64 64"
    role="img"
    :aria-label="site.brand"
  >
    <g fill="none">
      <circle
        cx="32"
        cy="32"
        r="19"
        stroke="currentColor"
        stroke-width="6.5"
        stroke-linecap="round"
        stroke-dasharray="16 13.845"
        transform="rotate(-24.1 32 32)"
      />
      <circle cx="32" cy="32" r="6.5" :class="bemm('dot')" />
    </g>
  </svg>
</template>

<style lang="scss">
.status-icon {
  display: block;
  height: 1em;
  width: 1em;

  &__dot {
    fill: var(--color-success);
  }
}
</style>