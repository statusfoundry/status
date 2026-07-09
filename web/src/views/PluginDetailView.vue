<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useBemm } from 'bemm'
import SiteLayout from '@/components/SiteLayout.vue'
import pluginsData from '@/generated/plugins.json'
import registryData from '@/generated/registry.json'

const bemm = useBemm('page', { return: 'string' })
const factsBemm = useBemm('plugin-facts', { return: 'string' })
const articleBemm = useBemm('plugin-readme', { return: 'string' })

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
</script>

<template>
  <SiteLayout>
    <main :class="bemm()">
      <template v-if="pluginDoc">
        <section :class="bemm('intro')">
          <div :class="bemm('container')">
            <p :class="bemm('eyebrow')">{{ trustLabel }}</p>
            <h1 :class="bemm('title')">{{ pluginDoc.name }}</h1>
            <p :class="bemm('subtitle')">{{ pluginDoc.summary }}</p>
            <div :class="bemm('links')">
              <RouterLink to="/plugins/">All plugins</RouterLink>
              <a :href="pluginDoc.sourceUrl" target="_blank" rel="noopener">Open README on GitHub</a>
            </div>
          </div>
        </section>

        <section :class="bemm('body')">
          <div :class="bemm('container')">
            <article :class="articleBemm()">
              <pre>{{ pluginDoc.readme }}</pre>
            </article>

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
                    <dt>Author</dt>
                    <dd>{{ pluginDoc.author }}</dd>
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

            <div v-if="release" :class="[bemm('container'), bemm('links'), bemm('links', 'distribution')]">
              <a v-if="release.manifestUrl" :href="release.manifestUrl">Manifest</a>
              <a v-if="release.packageUrl" :href="release.packageUrl">Package</a>
            </div>
          </div>
        </section>
      </template>

      <template v-else>
        <section :class="bemm('intro')">
          <div :class="bemm('container')">
            <p :class="bemm('eyebrow')">Plugin</p>
            <h1 :class="bemm('title')">Plugin not found.</h1>
            <p :class="bemm('subtitle')">This plugin does not have published documentation in the website index.</p>
            <div :class="bemm('links')">
              <RouterLink to="/plugins/">All plugins</RouterLink>
            </div>
          </div>
        </section>
      </template>
    </main>
  </SiteLayout>
</template>

<style lang="scss">
.plugin-readme {
  background: var(--color-surface);
  border: 1px solid var(--color-border-light);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-sm);
  margin-bottom: var(--space-l);
  padding: var(--space-l);

  pre {
    margin: 0;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    color: var(--color-text-primary);
    font-family: var(--font-family-monospace, ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace);
    font-size: var(--font-size-sm);
    line-height: var(--line-height-relaxed);
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

.page__grid--after-readme {
  margin-top: 0;
}

.page__links--distribution {
  padding-left: 0;
  padding-right: 0;
}
</style>