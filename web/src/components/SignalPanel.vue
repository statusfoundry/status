<script setup lang="ts">
import { useBemm } from 'bemm'
import { Card, Status, StatusBadge } from '@sil/ui'

const bemm = useBemm('signal-panel', { return: 'string' })

const signals = [
  { label: 'All apps okay', tone: Status.SUCCESS },
  { label: '1 app waiting for review', tone: Status.WARNING },
  { label: '1 workflow failed', tone: Status.ERROR },
]
</script>

<template>
  <Card :class="bemm()" title="Today">
    <ul :class="bemm('list')">
      <li v-for="signal in signals" :key="signal.label" :class="bemm('item')">
        <StatusBadge :label="signal.label" :tone="signal.tone" />
      </li>
    </ul>
  </Card>
</template>

<style lang="scss">
.signal-panel {
  &__list {
    display: grid;
    gap: var(--space-s);
    margin: 0;
    padding: 0;
    list-style: none;
  }

  &__item {
    display: flex;
  }
}
</style>