<script setup lang="ts">
import { useBemm } from 'bemm'

const bemm = useBemm('site-shell', { return: 'string' })
</script>

<template>
  <div :class="bemm()">
    <header :class="bemm('header')">
      <RouterLink :class="bemm('brand')" to="/">
        Status
      </RouterLink>
      <nav :class="bemm('nav')" aria-label="Primary navigation">
        <RouterLink to="/plugins/">Plugins</RouterLink>
        <RouterLink to="/developers/">Developers</RouterLink>
        <RouterLink to="/docs/">Docs</RouterLink>
        <a href="https://status-registry.hakobs.com/v1/plugins">Registry API</a>
      </nav>
    </header>

    <RouterView />
  </div>
</template>
