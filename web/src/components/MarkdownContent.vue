<script setup lang="ts">
import { useBemm } from 'bemm'

defineProps<{
  html: string
}>()

const bemm = useBemm('markdown-content', { return: 'string' })
</script>

<template>
  <article :class="['nizel-content', bemm()]" v-html="html" />
</template>