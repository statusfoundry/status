<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useBemm } from 'bemm'
import MarkdownContent from '@/components/MarkdownContent.vue'
import SiteLayout from '@/components/SiteLayout.vue'
import PluginPageLayout from '@/components/PluginPageLayout.vue'
import PluginIcon from '@/components/PluginIcon.vue'
import pluginsData from '@/generated/plugins.json'
import registryData from '@/generated/registry.json'

const bemm = useBemm('plugin-page', { return: 'string' })
const factsBemm = useBemm('plugin-facts', { return: 'string' })
const route = useRoute()

const pluginDoc = computed(() => {
  const pluginId = String(route.params.pluginId ?? '')
  return pluginsData.plugins.find((candidate) => candidate.id === pluginId)
})

const registryPlugin = computed(() => {
  const pluginId = String(route.params.pluginId ?? '')
  return registryData.plugins.find((candidate) => candidate.id === pluginId)
})

const release = computed(() => registryPlugin.value?.versions[0])

const pluginIcon = computed(() => pluginDoc.value?.icon ?? registryPlugin.value?.icon ?? null)
const pluginAccent = computed(
  () => pluginDoc.value?.accentColor ?? registryPlugin.value?.accentColor ?? null,
)
const pluginIconSvg = computed(() => pluginDoc.value?.iconSvg ?? null)

const trustLabel = computed(() => {
  const trustLevel = pluginDoc.value?.trustLevel ?? registryPlugin.value?.trustLevel
  if (trustLevel === 'official') return 'Official'
  if (trustLevel === 'verified-third-party') return 'Verified third party'
  if (trustLevel === 'local-dev') return 'Developer template'
  return 'Plugin'
})

const permissionList = computed(() => {
  const permissions = pluginDoc.value?.permissions ?? registryPlugin.value?.permissions ?? []
  return permissions.length ? permissions.join(', ') : 'No elevated permissions'
})

const domainList = computed(() => {
  const domains = pluginDoc.value?.domains ?? registryPlugin.value?.domains ?? []
  return domains.length ? domains.join(', ') : 'User-configured domains'
})

const sidebarPlugins = computed(() =>
  pluginsData.plugins.map((plugin) => ({
    id: plugin.id,
    name: plugin.name,
    summary: plugin.summary,
    websitePath: plugin.websitePath,
    published: plugin.published,
  })),
)

const readmeToc = computed(() => pluginDoc.value?.readmeToc ?? [])
</script>

<template>
  <SiteLayout>
    <main :class="bemm()">
      <template v-if="pluginDoc">
        <PluginPageLayout :plugins="sidebarPlugins" :sections="readmeToc">
          <header :class="bemm('header')">
            <p :class="bemm('eyebrow')">{{ trustLabel }}</p>
            <div :class="bemm('title-row')">
              <PluginIcon
                :name="pluginDoc.name"
                :accent-color="pluginAccent"
                :icon-svg="pluginIconSvg"
                size="lg"
              />
              <h1 :class="bemm('title')">{{ pluginDoc.name }}</h1>
            </div>
            <p :class="bemm('summary')">{{ pluginDoc.summary }}</p>
            <p v-if="pluginDoc.author" :class="bemm('author')">
              Author:
              <RouterLink v-if="pluginDoc.author.websitePath" :to="pluginDoc.author.websitePath">
                {{ pluginDoc.author.name }}
              </RouterLink>
              <template v-else>{{ pluginDoc.author.name }}</template>
            </p>
            <div :class="bemm('links')">
              <RouterLink to="/plugins/">All plugins</RouterLink>
              <a :href="pluginDoc.sourceUrl" target="_blank" rel="noopener">Open README on GitHub</a>
            </div>
          </header>

          <MarkdownContent :html="pluginDoc.readmeHtml" />

          <div :class="[bemm('grid'), bemm('grid', 'after-readme')]">
            <article :class="bemm('card')">
              <h2>Package</h2>
              <dl :class="factsBemm()">
                <div>
                  <dt>Plugin ID</dt>
                  <dd>{{ pluginDoc.id }}</dd>
                </div>
                <div>
                  <dt>Version</dt>
                  <dd>{{ release?.version ?? pluginDoc.version }}</dd>
                </div>
                <div>
                  <dt>Publisher</dt>
                  <dd>
                    <RouterLink v-if="pluginDoc.author.websitePath" :to="pluginDoc.author.websitePath">
                      {{ pluginDoc.author.name }}
                    </RouterLink>
                    <template v-else>{{ pluginDoc.author.name }}</template>
                  </dd>
                </div>
                <div>
                  <dt>Category</dt>
                  <dd>{{ pluginDoc.category }}</dd>
                </div>
                <div>
                  <dt>Published</dt>
                  <dd>{{ pluginDoc.published ? 'Registry' : 'Template only' }}</dd>
                </div>
              </dl>
            </article>

            <article :class="bemm('card')">
              <h2>Trust and access</h2>
              <dl :class="factsBemm()">
                <div>
                  <dt>Permissions</dt>
                  <dd>{{ permissionList }}</dd>
                </div>
                <div>
                  <dt>Domains</dt>
                  <dd>{{ domainList }}</dd>
                </div>
                <div v-if="release">
                  <dt>Signed by</dt>
                  <dd>{{ release.signedBy ?? 'Pending signature' }}</dd>
                </div>
                <div v-if="release">
                  <dt>SHA-256</dt>
                  <dd>{{ release.sha256 ?? 'Pending package' }}</dd>
                </div>
              </dl>
            </article>
          </div>

          <div v-if="release" :class="[bemm('links'), bemm('links', 'distribution')]">
            <a v-if="release.manifestUrl" :href="release.manifestUrl">Manifest</a>
            <a v-if="release.packageUrl" :href="release.packageUrl">Package</a>
          </div>
        </PluginPageLayout>
      </template>

      <template v-else>
        <PluginPageLayout :plugins="sidebarPlugins">
          <header :class="bemm('header')">
            <p :class="bemm('eyebrow')">Plugin</p>
            <h1 :class="bemm('title')">Plugin not found.</h1>
            <p :class="bemm('summary')">
              This plugin does not have published documentation in the website index.
            </p>
            <div :class="bemm('links')">
              <RouterLink to="/plugins/">All plugins</RouterLink>
            </div>
          </header>
        </PluginPageLayout>
      </template>
    </main>
  </SiteLayout>
</template>

<style lang="scss">
.plugin-page {
  background: var(--color-bg);
  color: var(--color-text-primary);

  &__header {
    margin-bottom: var(--space-l);
  }

  &__eyebrow {
    color: var(--color-accent);
    font-size: var(--font-size-sm);
    font-weight: var(--font-weight-semibold);
    margin-bottom: var(--space-s);
  }

  &__title-row {
    display: flex;
    align-items: center;
    gap: var(--space-m);
    margin-bottom: var(--space-s);
  }

  &__title {
    font-size: clamp(28px, 3.5vw, 40px);
    font-weight: var(--font-weight-bold);
    letter-spacing: -0.02em;
    line-height: var(--line-height-tight);
    margin: 0;
  }

  &__summary {
    color: var(--color-text-secondary);
    font-size: var(--font-size-base);
    line-height: var(--line-height-relaxed);
    margin-bottom: var(--space-s);
    max-width: 72ch;
  }

  &__author {
    color: var(--color-text-secondary);
    font-size: var(--font-size-sm);
    margin-bottom: var(--space-m);

    a {
      font-weight: var(--font-weight-semibold);
    }
  }

  &__links {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-s);

    a {
      border: 1px solid var(--color-border);
      border-radius: 999px;
      color: var(--color-foreground);
      font-size: var(--font-size-sm);
      font-weight: var(--font-weight-semibold);
      padding: var(--space-s) var(--space-m);
      text-decoration: none;
      transition: border-color var(--transition-fast), color var(--transition-fast);

      &:hover {
        border-color: var(--color-accent);
        color: var(--color-accent);
      }
    }
  }

  &__grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--space-l);
    margin-top: var(--space-l);

    @media (max-width: 720px) {
      grid-template-columns: 1fr;
    }
  }

  &__card {
    background: var(--color-surface);
    border: 1px solid var(--color-border-light);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-sm);
    padding: var(--space-l);

    h2 {
      margin: 0 0 var(--space-m);
      font-size: var(--font-size-lg);
      font-weight: var(--font-weight-semibold);
    }
  }

  &__links--distribution {
    margin-top: var(--space-l);
  }

  .markdown-content {
    margin-bottom: var(--space-l);
  }
}

.plugin-facts {
  display: grid;
  gap: var(--space-m);
  margin: 0;

  dt {
    color: var(--color-text-tertiary);
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-semibold);
    text-transform: uppercase;
  }

  dd {
    margin: var(--space-xs) 0 0;
    overflow-wrap: anywhere;
    line-height: var(--line-height-normal);
  }
}
</style>
