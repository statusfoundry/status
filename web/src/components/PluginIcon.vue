<script setup lang="ts">
import { computed } from 'vue'
import { useBemm } from 'bemm'

const props = withDefaults(
  defineProps<{
    name: string
    accentColor?: string | null
    iconSvg?: string | null
    size?: 'sm' | 'md' | 'lg'
  }>(),
  { accentColor: null, iconSvg: null, size: 'md' },
)

const bemm = useBemm('plugin-icon', { return: 'string' })

const initial = computed(() => props.name?.trim()?.charAt(0)?.toUpperCase() ?? '?')
const tileColor = computed(() => props.accentColor || 'var(--color-accent)')
</script>

<template>
  <span :class="[bemm(), bemm('', size)]" :style="{ '--plugin-accent': tileColor }">
    <span v-if="iconSvg" :class="bemm('svg')" v-html="iconSvg" />
    <span v-else :class="bemm('tile')">
      {{ initial }}
    </span>
  </span>
</template>

<style lang="scss">
.plugin-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  border-radius: var(--radius-md);
  overflow: hidden;

  &--sm {
    width: 32px;
    height: 32px;
  }

  &--md {
    width: 48px;
    height: 48px;
  }

  &--lg {
    width: 64px;
    height: 64px;
  }

  &__svg {
    display: flex;
    width: 100%;
    height: 100%;

    svg {
      width: 100%;
      height: 100%;
      display: block;
    }
  }

  &__tile {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    height: 100%;
    background: var(--plugin-accent);
    color: #fff;
    font-weight: var(--font-weight-bold);
    letter-spacing: -0.02em;
  }

  &--sm &__tile {
    font-size: var(--font-size-base);
  }

  &--md &__tile {
    font-size: var(--font-size-xl);
  }

  &--lg &__tile {
    font-size: var(--font-size-xxl);
  }
}
</style>
