<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useBemm } from 'bemm'
import SiteLayout from '@/components/SiteLayout.vue'
import registryData from '@/generated/registry.json'

const bemm = useBemm('page', { return: 'string' })
const factsBemm = useBemm('plugin-facts', { return: 'string' })

const route = useRoute()

const plugin = computed(() => {
  const pluginId = String(route.params.pluginId ?? '')
  return registryData.plugins.find((candidate) => candidate.id === pluginId)
})

const release = computed(() => plugin.value?.versions[0])
const trustLabel = computed(() => {
  if (plugin.value?.trustLevel === 'official') return 'Official'
  if (plugin.value?.trustLevel === 'verified-third-party') return 'Verified third party'
  return 'Local'
})

const permissionList = computed(() => plugin.value?.permissions.join(', ') || 'No elevated permissions')
const domainList = computed(() => plugin.value?.domains.join(', ') || 'User-configured domains')
</script>

<template>
  <SiteLayout>
    <main :class="bemm()">
      <template v-if="plugin">
        <section :class="bemm('intro')">
          <div :class="bemm('container')">
            <p :class="bemm('eyebrow')">{{ trustLabel }}</p>
            <h1 :class="bemm('title')">{{ plugin.name }}</h1>
            <p :class="bemm('subtitle')">{{ plugin.description }}</p>
          </div>
        </section>

        <section :class="bemm('body')">
          <div :class="[bemm('container'), bemm('grid')]">
            <article :class="bemm('card')">
              <h2>Package</h2>
              <dl :class="factsBemm()">
                <div>
                  <dt>Plugin ID</dt>
                  <dd>{{ plugin.id }}</dd>
                </div>
                <div>
                  <dt>Version</dt>
                  <dd>{{ release?.version ?? 'No release' }}</dd>
                </div>
                <div>
                  <dt>Author</dt>
                  <dd>{{ plugin.author }}</dd>
                </div>
                <div>
                  <dt>Category</dt>
                  <dd>{{ plugin.category }}</dd>
                </div>
              </dl>
            </article>

            <article :class="bemm('card')">
              <h2>Trust checks</h2>
              <dl :class="factsBemm()">
                <div>
                  <dt>Permissions</dt>
                  <dd>{{ permissionList }}</dd>
                </div>
                <div>
                  <dt>Domains</dt>
                  <dd>{{ domainList }}</dd>
                </div>
                <div>
                  <dt>Signed by</dt>
                  <dd>{{ release?.signedBy ?? 'Pending signature' }}</dd>
                </div>
                <div>
                  <dt>SHA-256</dt>
                  <dd>{{ release?.sha256 ?? 'Pending package' }}</dd>
                </div>
              </dl>
            </article>
          </div>

          <div :class="[bemm('container'), bemm('links')]">
            <a v-if="release?.manifestUrl" :href="release.manifestUrl">Manifest</a>
            <a v-if="release?.packageUrl" :href="release.packageUrl">Package</a>
            <RouterLink to="/plugins/">Back to plugins</RouterLink>
          </div>
        </section>
      </template>

      <template v-else>
        <section :class="bemm('intro')">
          <div :class="bemm('container')">
            <p :class="bemm('eyebrow')">Plugin</p>
            <h1 :class="bemm('title')">Plugin not found.</h1>
            <p :class="bemm('subtitle')">The registry does not list this plugin.</p>
            <div :class="bemm('links')">
              <RouterLink to="/plugins/">Back to plugins</RouterLink>
            </div>
          </div>
        </section>
      </template>
    </main>
  </SiteLayout>
</template>

<style lang="scss">
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