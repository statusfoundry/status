<script setup lang="ts">
import { useBemm } from 'bemm'
import SiteLayout from '@/components/SiteLayout.vue'
import guide from '@/content/developer-guide.json'

const bemm = useBemm('page', { return: 'string' })
const devBemm = useBemm('developers-guide', { return: 'string' })
</script>

<template>
  <SiteLayout>
    <main :class="bemm()">
      <section :class="bemm('intro')">
        <div :class="bemm('container')">
          <p :class="bemm('eyebrow')">Developers</p>
          <h1 :class="bemm('title')">Build a declarative plugin.</h1>
          <p :class="bemm('subtitle')">
            Plugins are signed data packages. Status owns the UI, credentials, notifications, and audit output.
            Start from the example template, validate locally, test in Developer Mode, then submit through review.
          </p>
          <div :class="bemm('links')">
            <RouterLink to="/docs/plugin-author-guide/">Read the full guide</RouterLink>
            <a :href="guide.template.standaloneUrl" target="_blank" rel="noopener">Fork example template</a>
          </div>
        </div>
      </section>

      <section :class="bemm('body')">
        <div :class="bemm('container')">
          <div :class="devBemm('sections')">
            <article :class="[bemm('card'), devBemm('card')]">
              <h2>{{ guide.template.title }}</h2>
              <p>{{ guide.template.summary }}</p>
              <p>
                Current path:
                <code>{{ guide.template.monorepoPath }}</code>
              </p>
              <p>
                Standalone template:
                <code>{{ guide.template.standaloneRepo }}</code>
              </p>
              <a :href="guide.template.standaloneUrl" target="_blank" rel="noopener">
                Fork standalone template
              </a>
              <a :href="guide.template.monorepoUrl" target="_blank" rel="noopener">
                View monorepo copy
              </a>
            </article>

            <article :class="[bemm('card'), devBemm('card')]">
              <h2>Local commands</h2>
              <div
                v-for="item in guide.commands"
                :key="item.label"
                :class="devBemm('command')"
              >
                <p :class="devBemm('command-label')">{{ item.label }}</p>
                <pre :class="devBemm('command-code')"><code>{{ item.command }}</code></pre>
              </div>
            </article>

            <article :class="[bemm('card'), devBemm('card'), devBemm('card', 'wide')]">
              <h2>Workflow</h2>
              <ol :class="devBemm('workflow')">
                <li v-for="step in guide.workflow" :key="step.title">
                  <strong>{{ step.title }}</strong>
                  <span>{{ step.body }}</span>
                </li>
              </ol>
            </article>

            <article :class="[bemm('card'), devBemm('card'), devBemm('card', 'wide')]">
              <h2>Hosting model</h2>
              <div :class="devBemm('split-list')">
                <section v-for="item in guide.hosting" :key="item.title">
                  <h3>{{ item.title }}</h3>
                  <p>{{ item.body }}</p>
                </section>
              </div>
            </article>

            <article :class="[bemm('card'), devBemm('card'), devBemm('card', 'wide')]">
              <h2>Governance model</h2>
              <div :class="devBemm('split-list')">
                <section v-for="item in guide.governance" :key="item.title">
                  <h3>{{ item.title }}</h3>
                  <p>{{ item.body }}</p>
                </section>
              </div>
            </article>

            <article :class="[bemm('card'), devBemm('card')]">
              <h2>Submission path</h2>
              <ol :class="devBemm('workflow')">
                <li v-for="item in guide.submission" :key="item.title">
                  <strong>{{ item.title }}</strong>
                  <span>{{ item.body }}</span>
                </li>
              </ol>
            </article>

            <article :class="[bemm('card'), devBemm('card')]">
              <h2>Trust levels</h2>
              <dl :class="devBemm('files')">
                <div v-for="item in guide.trustLevels" :key="item.level">
                  <dt><code>{{ item.level }}</code></dt>
                  <dd>{{ item.body }}</dd>
                </div>
              </dl>
            </article>

            <article :class="[bemm('card'), devBemm('card'), devBemm('card', 'wide')]">
              <h2>Install verification</h2>
              <ol :class="devBemm('workflow')">
                <li v-for="item in guide.downloadFlow" :key="item">
                  <span>{{ item }}</span>
                </li>
              </ol>
            </article>

            <article :class="[bemm('card'), devBemm('card')]">
              <h2>Package files</h2>
              <dl :class="devBemm('files')">
                <div v-for="file in guide.packageFiles" :key="file.file">
                  <dt><code>{{ file.file }}</code></dt>
                  <dd>{{ file.purpose }}</dd>
                </div>
              </dl>
            </article>

            <article :class="[bemm('card'), devBemm('card')]">
              <h2>V1 restrictions</h2>
              <ul>
                <li v-for="item in guide.restrictions" :key="item">{{ item }}</li>
              </ul>
            </article>

            <article :class="[bemm('card'), devBemm('card'), devBemm('card', 'wide')]">
              <h2>Related docs</h2>
              <div :class="devBemm('doc-links')">
                <RouterLink
                  v-for="doc in guide.relatedDocs"
                  :key="doc.slug"
                  :to="`/docs/${doc.slug}/`"
                >
                  {{ doc.label }}
                </RouterLink>
              </div>
            </article>
          </div>
        </div>
      </section>
    </main>
  </SiteLayout>
</template>

<style lang="scss">
.developers-guide {
  &__sections {
    display: grid;
    gap: var(--space-m);
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  &__card {
    code {
      font-family: var(--font-family-monospace, ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace);
      font-size: var(--font-size-sm);
    }

    a {
      display: inline-flex;
      margin-top: var(--space-s);
      font-weight: var(--font-weight-semibold);
    }
  }

  &__card--wide {
    grid-column: 1 / -1;
  }

  &__command {
    & + & {
      margin-top: var(--space-m);
    }
  }

  &__command-label {
    color: var(--color-text-secondary);
    font-size: var(--font-size-sm);
    font-weight: var(--font-weight-semibold);
    margin-bottom: var(--space-xs);
  }

  &__command-code {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border-light);
    border-radius: var(--radius-md);
    margin: 0;
    overflow-x: auto;
    padding: var(--space-s) var(--space-m);

    code {
      color: var(--color-text-primary);
      white-space: pre-wrap;
    }
  }

  &__workflow {
    display: grid;
    gap: var(--space-m);
    list-style: none;
    margin: 0;
    padding: 0;

    li {
      display: grid;
      gap: var(--space-xs);
    }

    strong {
      font-size: var(--font-size-base);
    }

    span {
      color: var(--color-text-secondary);
      line-height: var(--line-height-relaxed);
    }
  }

  &__files {
    display: grid;
    gap: var(--space-s);
    margin: 0;

    dt {
      font-weight: var(--font-weight-semibold);
    }

    dd {
      color: var(--color-text-secondary);
      line-height: var(--line-height-relaxed);
      margin: var(--space-xs) 0 0;
    }
  }

  &__split-list {
    display: grid;
    gap: var(--space-m);
    grid-template-columns: repeat(3, minmax(0, 1fr));

    section {
      display: grid;
      gap: var(--space-xs);
    }

    h3 {
      font-size: var(--font-size-base);
      margin: 0;
    }

    p {
      color: var(--color-text-secondary);
      line-height: var(--line-height-relaxed);
      margin: 0;
    }
  }

  &__doc-links {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-s);

    a {
      border: 1px solid var(--color-border);
      border-radius: 999px;
      color: var(--color-foreground);
      font-size: var(--font-size-sm);
      font-weight: var(--font-weight-semibold);
      margin-top: 0;
      padding: var(--space-s) var(--space-m);
      text-decoration: none;

      &:hover {
        border-color: var(--color-accent);
        color: var(--color-accent);
      }
    }
  }

  @media (max-width: 820px) {
    &__sections {
      grid-template-columns: 1fr;
    }

    &__card--wide {
      grid-column: auto;
    }

    &__split-list {
      grid-template-columns: 1fr;
    }
  }
}
</style>
