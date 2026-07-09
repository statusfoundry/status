<script setup lang="ts">
import { computed, ref } from 'vue'
import { useBemm } from 'bemm'
import { Icons, PillHeader, type PillHeaderAction, type PillHeaderNavItem } from '@sil/ui'
import StatusIcon from '@/components/Icon.vue'
import site from '@/content/site.json'

const bemm = useBemm('site-header', { return: 'string' })
const isDark = ref(false)

const navItems = site.header.nav as PillHeaderNavItem[]

function toggleTheme() {
  isDark.value = !isDark.value
  document.documentElement.classList.toggle('dark', isDark.value)
}

const actions = computed<PillHeaderAction[]>(() => [
  {
    label: site.header.toggleColorMode,
    icon: isDark.value ? Icons.WEATHER_SUN_LIGHT_MODE : Icons.WEATHER_MOON_DARK_MODE,
    iconOnly: true,
    handler: toggleTheme,
  },
])
</script>

<template>
  <PillHeader
    :class="bemm()"
    brand-to="/"
    :brand-aria-label="site.header.brandAriaLabel"
    color-mode="dark"
    :actions="actions"
    :nav-items="navItems"
  >
    <template #brand-mark>
      <StatusIcon :class="bemm('icon')" aria-hidden="true" />
    </template>
    <template #default>
      <span :class="bemm('name')">{{ site.brand }}</span>
    </template>
  </PillHeader>
</template>

<style lang="scss">
.site-header {
  --pill-header-position: sticky;
  top: 0;
  z-index: 10;

  &__icon {
    color: var(--color-accent);
    width: 24px;
    height: 24px;
  }

  &__name {
    font-weight: var(--font-weight-bold);
  }
}
</style>