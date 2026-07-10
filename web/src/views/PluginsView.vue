<script setup lang="ts">
import { useBemm } from 'bemm'
import SiteLayout from '@/components/SiteLayout.vue'
import PluginIcon from '@/components/PluginIcon.vue'
import pluginsData from '@/generated/plugins.json'
import registryData from '@/generated/registry.json'

const pluginDocsById = Object.fromEntries(pluginsData.plugins.map((plugin) => [plugin.id, plugin]))

const bemm = useBemm('page', { return: 'string' })
const directoryBemm = useBemm('plugins-directory', { return: 'string' })

type RegistryPlugin = (typeof registryData.plugins)[number]
type PluginDoc = (typeof pluginsData.plugins)[number]

const plugins = registryData.plugins.map((plugin) => ({
  ...plugin,
  author: pluginDocsById[plugin.id]?.author ?? plugin.author,
  iconSvg: pluginDocsById[plugin.id]?.iconSvg ?? null,
}))
const templatePlugins = pluginsData.plugins.filter((plugin) => plugin.published === false)
const registryChecks = [
  'Local hash verification',
  'Signature material verification',
  'Compatibility checks',
  'Permission review',
  'Revocation checks',
]

function trustLabel(plugin: RegistryPlugin) {
  if (plugin.trustLevel === 'official') return 'Official'
  if (plugin.trustLevel === 'verified-third-party') return 'Verified'
  return 'Local'
}

function versionLabel(plugin: RegistryPlugin) {
  return plugin.versions[0]?.version ?? 'No release'
}

function permissionLabel(plugin: RegistryPlugin) {
  return plugin.permissions.length ? plugin.permissions.join(', ') : 'No elevated permissions'
}

function domainLabel(plugin: RegistryPlugin) {
  return plugin.domains.length ? plugin.domains.join(', ') : 'User-defined targets'
}

function templateTrustLabel(plugin: PluginDoc) {
  if (plugin.trustLevel === 'local-dev') return 'Template'
  return 'Docs'
}
</script>

<template>
  <SiteLayout>
    <main :class="bemm()">
      <section :class="bemm('intro')">
        <div :class="bemm('container')">
          <p :class="bemm('eyebrow')">Plugins</p>
          <h1 :class="bemm('title')">Reviewed, signed plugin distribution.</h1>
          <p :class="bemm('subtitle')">
            Official and reviewed third-party plugins are published through the registry only after validation,
            review, signing, and immutable R2 upload.
          </p>
        </div>
      </section>

      <section :class="bemm('body')">
        <div :class="bemm('container')">
          <div :class="bemm('grid')">
            <article :class="bemm('card')">
              <h2>Registry API</h2>
              <p>
                <a href="https://status-registry.hakobs.com/v1/plugins">status-registry.hakobs.com/v1/plugins</a>
              </p>
            </article>
            <article :class="bemm('card')">
              <h2>Trust model</h2>
              <ul>
                <li v-for="check in registryChecks" :key="check">{{ check }}</li>
              </ul>
            </article>
          </div>

          <div :class="directoryBemm()" aria-label="Plugin directory">
            <article v-for="plugin in plugins" :key="plugin.id" :class="directoryBemm('item')">
              <div :class="directoryBemm('head')">
                <PluginIcon
                  :name="plugin.name"
                  :accent-color="plugin.accentColor"
                  :icon-svg="plugin.iconSvg"
                  size="md"
                />
                <div :class="directoryBemm('head-text')">
                  <h2>{{ plugin.name }}</h2>
                  <p>{{ plugin.summary }}</p>
                  <p v-if="plugin.author?.name" :class="directoryBemm('author')">
                    Author:
                    <RouterLink
                      v-if="plugin.author.websitePath"
                      :to="plugin.author.websitePath"
                    >
                      {{ plugin.author.name }}
                    </RouterLink>
                    <template v-else>{{ plugin.author.name }}</template>
                  </p>
                </div>
                <span :class="directoryBemm('badge')">{{ trustLabel(plugin) }}</span>
              </div>
              <dl :class="directoryBemm('meta')">
                <div>
                  <dt>Version</dt>
                  <dd>{{ versionLabel(plugin) }}</dd>
                </div>
                <div>
                  <dt>Permissions</dt>
                  <dd>{{ permissionLabel(plugin) }}</dd>
                </div>
                <div>
                  <dt>Domains</dt>
                  <dd>{{ domainLabel(plugin) }}</dd>
                </div>
              </dl>
              <RouterLink :class="directoryBemm('link')" :to="`/plugins/${plugin.id}/`">
                Read plugin docs
              </RouterLink>
            </article>
          </div>

          <div v-if="templatePlugins.length" :class="directoryBemm()" aria-label="Plugin templates">
            <h2 :class="directoryBemm('section-title')">Templates and examples</h2>
            <article v-for="plugin in templatePlugins" :key="plugin.id" :class="directoryBemm('item')">
              <div :class="directoryBemm('head')">
                <PluginIcon
                  :name="plugin.name"
                  :accent-color="plugin.accentColor"
                  :icon-svg="plugin.iconSvg"
                  size="md"
                />
                <div :class="directoryBemm('head-text')">
                  <h3>{{ plugin.name }}</h3>
                  <p>{{ plugin.summary }}</p>
                </div>
                <span :class="directoryBemm('badge')">{{ templateTrustLabel(plugin) }}</span>
              </div>
              <RouterLink :class="directoryBemm('link')" :to="plugin.websitePath">
                Read plugin docs
              </RouterLink>
            </article>
          </div>
        </div>
      </section>
    </main>
  </SiteLayout>
</template>

<style lang="scss">
.plugins-directory {
  display: grid;
  gap: var(--space-m);
  margin-top: var(--space-l);

  &__section-title {
    margin: 0;
    font-size: var(--font-size-lg);
    font-weight: var(--font-weight-semibold);
  }

  &__item {
    background: var(--color-surface);
    border: 1px solid var(--color-border-light);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-sm);
    padding: var(--space-l);
  }

  &__head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-m);
  }

  &__head-text {
    flex: 1;
    min-width: 0;

    h2,
    h3 {
      margin: 0;
      font-size: var(--font-size-lg);
      font-weight: var(--font-weight-semibold);
    }

    p {
      margin: var(--space-xs) 0 0;
      color: var(--color-text-secondary);
      line-height: var(--line-height-relaxed);
    }
  }

  &__author {
    font-size: var(--font-size-sm);

    a {
      font-weight: var(--font-weight-semibold);
    }
  }

  &__badge {
    border: 1px solid var(--color-border);
    border-radius: 999px;
    color: var(--color-text-secondary);
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-semibold);
    padding: var(--space-xs) var(--space-s);
    white-space: nowrap;
  }

  &__meta {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: var(--space-m);
    margin: var(--space-m) 0 0;

    dt {
      color: var(--color-text-tertiary);
      font-size: var(--font-size-xs);
      font-weight: var(--font-weight-semibold);
      text-transform: uppercase;
    }

    dd {
      margin: var(--space-xs) 0 0;
      overflow-wrap: anywhere;
      font-size: var(--font-size-sm);
      line-height: var(--line-height-normal);
    }
  }

  &__link {
    display: inline-flex;
    margin-top: var(--space-m);
    font-weight: var(--font-weight-semibold);
  }

  @media (max-width: 820px) {
    &__head,
    &__meta {
      grid-template-columns: 1fr;
      display: grid;
    }

    &__head {
      display: flex;
      flex-wrap: wrap;
    }
  }
}
</style>