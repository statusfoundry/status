<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute } from 'vue-router'
import { useBemm } from 'bemm'
import type { DocTocEntry } from '@/components/DocSidebar.vue'

export type PluginListItem = {
  id: string
  name: string
  summary: string
  websitePath: string
  published: boolean
}

const props = defineProps<{
  plugins: PluginListItem[]
  sections?: DocTocEntry[]
}>()

const bemm = useBemm('plugin-sidebar', { return: 'string' })
const route = useRoute()

const activeId = computed(() => String(route.params.pluginId ?? ''))
const filter = ref('')

const publishedPlugins = computed(() => props.plugins.filter((plugin) => plugin.published))
const templatePlugins = computed(() => props.plugins.filter((plugin) => !plugin.published))

const filteredPublished = computed(() => {
  const query = filter.value.trim().toLowerCase()
  if (!query) return publishedPlugins.value
  return publishedPlugins.value.filter(
    (plugin) =>
      plugin.name.toLowerCase().includes(query) || plugin.summary.toLowerCase().includes(query),
  )
})

const filteredTemplates = computed(() => {
  const query = filter.value.trim().toLowerCase()
  if (!query) return templatePlugins.value
  return templatePlugins.value.filter(
    (plugin) =>
      plugin.name.toLowerCase().includes(query) || plugin.summary.toLowerCase().includes(query),
  )
})

const sectionLinks = computed(() => props.sections?.filter((entry) => entry.depth <= 3) ?? [])
</script>

<template>
  <aside :class="bemm()">
    <nav :class="bemm('nav')" aria-label="Plugins">
      <div :class="bemm('group')">
        <p :class="bemm('label')">Plugins</p>
        <div :class="bemm('filter')">
          <input
            v-model="filter"
            type="search"
            placeholder="Filter plugins"
            :class="bemm('filter-input')"
            aria-label="Filter plugins"
          />
        </div>
        <ul :class="bemm('list')">
          <li v-for="plugin in filteredPublished" :key="plugin.id">
            <RouterLink
              :to="plugin.websitePath"
              :class="[bemm('link'), { [bemm('link', 'active')]: plugin.id === activeId }]"
            >
              {{ plugin.name }}
            </RouterLink>
          </li>
        </ul>
        <template v-if="filteredTemplates.length">
          <p :class="[bemm('label'), bemm('label', 'sub')]">Templates</p>
          <ul :class="bemm('list')">
            <li v-for="plugin in filteredTemplates" :key="plugin.id">
              <RouterLink
                :to="plugin.websitePath"
                :class="[bemm('link'), { [bemm('link', 'active')]: plugin.id === activeId }]"
              >
                {{ plugin.name }}
              </RouterLink>
            </li>
          </ul>
        </template>
        <p v-if="!filteredPublished.length && !filteredTemplates.length" :class="bemm('empty')">
          No plugins match "{{ filter }}".
        </p>
      </div>

      <div v-if="sectionLinks.length" :class="bemm('group')">
        <p :class="bemm('label')">On this page</p>
        <ul :class="[bemm('list'), bemm('list', 'sections')]">
          <li
            v-for="section in sectionLinks"
            :key="section.id"
            :class="bemm('section-item', String(section.depth))"
          >
            <a :href="`#${section.id}`" :class="bemm('section-link')">
              {{ section.text }}
            </a>
          </li>
        </ul>
      </div>
    </nav>
  </aside>
</template>

<style lang="scss">
.plugin-sidebar {
  position: sticky;
  top: calc(var(--space-l) + var(--space-m));
  align-self: start;
  max-height: calc(100vh - var(--space-xxl));
  overflow-y: auto;
  padding-right: var(--space-s);

  &__nav {
    display: grid;
    gap: var(--space-l);
  }

  &__group {
    display: grid;
    gap: var(--space-s);
  }

  &__label {
    color: var(--color-text-tertiary);
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-semibold);
    letter-spacing: 0.06em;
    text-transform: uppercase;
    margin: 0;

    &--sub {
      margin-top: var(--space-m);
    }
  }

  &__filter {
    display: flex;
  }

  &__filter-input {
    width: 100%;
    border: 1px solid var(--color-border-light);
    border-radius: var(--radius-sm);
    background: var(--color-surface);
    color: var(--color-text-primary);
    font-size: var(--font-size-sm);
    padding: var(--space-xs) var(--space-s);
    outline: none;
    transition: border-color var(--transition-fast);

    &::placeholder {
      color: var(--color-text-tertiary);
    }

    &:focus {
      border-color: var(--color-accent);
    }
  }

  &__list {
    display: grid;
    gap: var(--space-xs);
    list-style: none;
    margin: 0;
    padding: 0;
  }

  &__link {
    border-left: 2px solid transparent;
    color: var(--color-text-secondary);
    display: block;
    font-size: var(--font-size-sm);
    line-height: var(--line-height-normal);
    padding: var(--space-xs) 0 var(--space-xs) var(--space-s);
    text-decoration: none;
    transition: border-color var(--transition-fast), color var(--transition-fast);

    &:hover {
      color: var(--color-text-primary);
    }

    &--active {
      border-left-color: var(--color-accent);
      color: var(--color-text-primary);
      font-weight: var(--font-weight-semibold);
    }
  }

  &__empty {
    color: var(--color-text-tertiary);
    font-size: var(--font-size-sm);
    margin: 0;
  }

  &__section-link {
    color: var(--color-text-secondary);
    display: block;
    font-size: var(--font-size-sm);
    line-height: var(--line-height-normal);
    padding: 2px 0;
    text-decoration: none;
    transition: color var(--transition-fast);

    &:hover {
      color: var(--color-accent);
    }
  }

  &__section-item--3 {
    padding-left: var(--space-s);
  }

  &__section-item--4,
  &__section-item--5,
  &__section-item--6 {
    padding-left: var(--space-m);
  }
}
</style>
