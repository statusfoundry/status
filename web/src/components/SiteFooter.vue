<script setup lang="ts">
import { useBemm } from 'bemm'
import { PlatformFooter } from '@sil/ui'
import { RouterLink } from 'vue-router'
import site from '@/content/site.json'

const bemm = useBemm('footer', { return: 'string' })
</script>

<template>
  <PlatformFooter max-width="1120px" color-mode="auto">
    <template #brand>
      <span :class="bemm('brand')">{{ site.brand }}</span>
    </template>

    <template #nav>
      <nav :class="bemm('links')" :aria-label="site.footer.ariaLabel">
        <template v-for="item in site.footer.nav" :key="item.label">
          <RouterLink v-if="item.to" :to="item.to">{{ item.label }}</RouterLink>
          <a v-else :href="item.href" target="_blank" rel="noopener">{{ item.label }}</a>
        </template>
      </nav>
    </template>

    <template #meta>
      <p :class="bemm('copy')">
        &copy; {{ new Date().getFullYear() }} {{ site.footer.copyrightPrefix }}
        <a :href="site.footer.developerUrl">{{ site.footer.developerLabel }}</a>
      </p>
    </template>
  </PlatformFooter>
</template>

<style lang="scss">
.footer__brand {
  font-size: var(--font-size-md);
  font-weight: var(--font-weight-bold);
  color: var(--color-text-primary);
}

.footer__links {
  display: flex;
  align-items: center;
  gap: var(--space-l);
  flex-wrap: wrap;

  a {
    font-size: var(--font-size-sm);
    color: var(--color-text-tertiary);
    text-decoration: none;
    transition: color var(--transition-fast);

    &:hover {
      color: var(--color-text-primary);
    }
  }
}

.footer__copy {
  font-size: var(--font-size-xs);
  color: var(--color-text-tertiary);

  a {
    color: var(--color-text-tertiary);

    &:hover {
      color: var(--color-accent);
    }
  }
}
</style>