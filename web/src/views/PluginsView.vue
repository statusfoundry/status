<script setup lang="ts">
import { Badge, Card } from '@sil/ui'
import { useBemm } from 'bemm'
import registryData from '../generated/registry.json'

const bemm = useBemm('plugins-view', { return: 'string' })

type RegistryPlugin = (typeof registryData.plugins)[number]

const plugins = registryData.plugins
const registryChecks = [
  'Local hash verification',
  'Signature material verification',
  'Compatibility checks',
  'Permission review',
  'Revocation checks',
]

function trustLabel(plugin: RegistryPlugin) {
  if (plugin.trustLevel === 'official') {
    return 'Official'
  }
  if (plugin.trustLevel === 'verified-third-party') {
    return 'Verified'
  }
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
</script>

<template>
  <main :class="bemm()">
    <section :class="bemm('intro')">
      <Badge variant="outline">Plugins</Badge>
      <h1>Reviewed, signed plugin distribution.</h1>
      <p>
        Official and reviewed third-party plugins are published through the registry only after validation,
        review, signing, and immutable R2 upload.
      </p>
    </section>

    <section :class="bemm('grid')">
      <Card title="Registry API">
        <p>
          <a href="https://status-registry.hakobs.com/v1/plugins">status-registry.hakobs.com/v1/plugins</a>
        </p>
      </Card>
      <Card title="Trust model">
        <ul>
          <li v-for="check in registryChecks" :key="check">{{ check }}</li>
        </ul>
      </Card>
    </section>

    <section :class="bemm('directory')" aria-label="Plugin directory">
      <article v-for="plugin in plugins" :key="plugin.id" :class="bemm('plugin')">
        <div :class="bemm('plugin-head')">
          <div>
            <h2>{{ plugin.name }}</h2>
            <p>{{ plugin.summary }}</p>
          </div>
          <Badge variant="outline">{{ trustLabel(plugin) }}</Badge>
        </div>
        <dl :class="bemm('plugin-meta')">
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
      </article>
    </section>
  </main>
</template>
