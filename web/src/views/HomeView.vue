<script setup lang="ts">
import { useBemm } from 'bemm'
import { Icon, Icons } from '@sil/ui'
import { RouterLink } from 'vue-router'

const bemm = useBemm('landing', { return: 'string' })
import Logo from '@/components/Logo.vue'
import SignalPanel from '@/components/SignalPanel.vue'
import SiteFooter from '@/components/SiteFooter.vue'
import SiteHeader from '@/components/SiteHeader.vue'

const pillars = [
  {
    title: 'Native first',
    description: 'A real macOS and iOS app with shared core logic and platform-native views.',
    icon: Icons.MISC_AI_ROBOT,
    docsId: 'architecture',
  },
  {
    title: 'Event-based',
    description: 'Triggers, jobs, events, rules, actions, notifications, and audit logs follow one explainable pipeline.',
    icon: Icons.WEATHER_LIGHTNING_FLASH,
    docsId: 'events-automation',
  },
  {
    title: 'Plugin-powered',
    description: 'Declarative adapters normalize tools into common resources, events, metrics, and actions.',
    icon: Icons.UI_CODE_CHEVRONS_OPEN,
    docsId: 'plugin-system',
  },
]

const pipeline = [
  { label: 'Trigger', value: 'Schedules and manual refresh start the work.' },
  { label: 'Event', value: 'Normalized changes flow through one explainable bus.' },
  { label: 'Action', value: 'Notifications, inbox items, and approved writes stay auditable.' },
]
</script>

<template>
  <div :class="bemm()">
    <SiteHeader />

    <section :class="bemm('hero')">
      <div :class="[bemm('container'), bemm('hero-layout')]">
        <div :class="bemm('hero-copy')">
          <Logo :class="bemm('hero-logo')" />
          <p :class="bemm('hero-eyebrow')">Native personal operations hub</p>
          <h1 :class="bemm('hero-title')">A native status layer for everything you run.</h1>
          <p :class="bemm('hero-subtitle')">
            Connect your tools. See what changed. Act only when needed.
          </p>
          <div :class="bemm('hero-actions')">
            <RouterLink :class="bemm('btn-pill')" to="/download/">
              <Icon :name="Icons.ARROWS_ARROW_DOWNLOAD" size="small" aria-hidden="true" />
              Get beta
            </RouterLink>
            <RouterLink :class="bemm('btn-outline')" to="/docs/">
              <Icon :name="Icons.UI_FILE_EDIT" size="small" aria-hidden="true" />
              Read docs
            </RouterLink>
          </div>
          <div :class="bemm('hero-strip')" aria-hidden="true">
            <span><Icon :name="Icons.UI_FILE_EDIT" size="small" /></span>
            <span><Icon :name="Icons.WEATHER_LIGHTNING_FLASH" size="small" /></span>
            <span><Icon :name="Icons.UI_CODE_CHEVRONS_OPEN" size="small" /></span>
            <span><Icon :name="Icons.ARROWS_ARROW_DOWNLOAD" size="small" /></span>
          </div>
        </div>
        <SignalPanel :class="bemm('signal-panel')" />
      </div>
    </section>

    <section :class="bemm('pipeline')">
      <div :class="[bemm('container'), bemm('pipeline-content')]">
        <div>
          <h2 :class="bemm('pipeline-title')">One pipeline, many tools.</h2>
          <p :class="bemm('pipeline-subtitle')">
            Status keeps the product calm by routing every integration through the same event model.
          </p>
        </div>
        <div :class="bemm('pipeline-points')">
          <div v-for="point in pipeline" :key="point.label" :class="bemm('pipeline-point')">
            <strong>{{ point.label }}</strong>
            <span>{{ point.value }}</span>
          </div>
        </div>
      </div>
    </section>

    <section id="features" :class="bemm('features')">
      <div :class="bemm('container')">
        <h2 :class="bemm('section-title')">Built for operational clarity</h2>
        <p :class="bemm('section-subtitle')">
          Native app first. Declarative plugins. Explicit permissions. Local-first for v1.
        </p>
        <div :class="bemm('grid')">
          <RouterLink
            v-for="pillar in pillars"
            :key="pillar.title"
            :class="bemm('card')"
            :to="`/docs/${pillar.docsId}/`"
          >
            <Icon :class="bemm('card-icon')" :name="pillar.icon" size="large" aria-hidden="true" />
            <h3 :class="bemm('card-title')">{{ pillar.title }}</h3>
            <p :class="bemm('card-desc')">{{ pillar.description }}</p>
          </RouterLink>
        </div>
      </div>
    </section>

    <section :class="bemm('cta')">
      <div :class="bemm('container')">
        <h2 :class="bemm('cta-title')">Start with read-only integrations.</h2>
        <p :class="bemm('cta-subtitle')">
          Review official plugins, inspect permissions, and enable actions only when you need them.
        </p>
        <div :class="bemm('cta-actions')">
          <RouterLink :class="bemm('btn-pill', 'lg')" to="/plugins/">
            <Icon :name="Icons.UI_CODE_CHEVRONS_OPEN" size="small" aria-hidden="true" />
            Browse plugins
          </RouterLink>
          <RouterLink :class="bemm('btn-outline')" to="/developers/">
            <Icon :name="Icons.UI_FILE_EDIT" size="small" aria-hidden="true" />
            Build a plugin
          </RouterLink>
        </div>
      </div>
    </section>

    <section id="developer" :class="bemm('developer')">
      <div :class="[bemm('container'), bemm('developer-content')]">
        <div>
          <h2 :class="bemm('developer-title')">Documentation-led by design.</h2>
          <p :class="bemm('developer-subtitle')">
            Status is defined by doctrine, spec, and implementation contracts before code ships.
            Plugins stay declarative. The app owns all UI.
          </p>
        </div>
        <RouterLink :class="[bemm('btn-outline'), bemm('developer-link')]" to="/docs/">
          <Icon :name="Icons.UI_CODE_CHEVRONS_OPEN" size="small" aria-hidden="true" />
          Read the docs
        </RouterLink>
      </div>
    </section>

    <SiteFooter />
  </div>
</template>

<style lang="scss">
.landing {
  min-height: 100vh;
  background: var(--color-bg);

  &__container {
    max-width: 1120px;
    margin: 0 auto;
    padding: 0 var(--space-l);
  }

  @include e(btn-pill) {
    display: inline-flex;
    align-items: center;
    gap: var(--space-xs);
    font-weight: var(--font-weight-semibold);
    color: #fff;
    background: var(--color-accent);
    padding: var(--space-s) var(--space-m);
    border-radius: 999px;
    font-size: var(--font-size-sm);
    transition: all var(--transition-fast);

    &:hover {
      background: var(--color-accent-dark);
      color: #fff;
      transform: translateY(-1px);
    }

    @include m(lg) {
      font-size: var(--font-size-base);
      padding: var(--space-s) var(--space-l);
    }
  }

  @include e(btn-outline) {
    display: inline-flex;
    align-items: center;
    gap: var(--space-xs);
    font-weight: var(--font-weight-medium);
    color: var(--color-text-secondary);
    background: transparent;
    border: 1px solid var(--color-border);
    padding: 9px var(--space-m);
    border-radius: 999px;
    font-size: var(--font-size-sm);
    transition: all var(--transition-fast);

    &:hover {
      border-color: var(--color-accent);
      color: var(--color-text-primary);
      transform: translateY(-1px);
    }
  }

  @include e(hero) {
    overflow: hidden;
    padding: var(--space-xl) 0;
    position: relative;

    &::before {
      background: linear-gradient(
        115deg,
        transparent 0%,
        transparent 38%,
        color-mix(in srgb, var(--color-accent), transparent 88%) 50%,
        transparent 62%,
        transparent 100%
      );
      content: '';
      inset: 0;
      pointer-events: none;
      position: absolute;
      transform: translateX(-65%);
    }
  }

  @include e(hero-layout) {
    display: grid;
    grid-template-columns: minmax(0, 1.15fr) minmax(300px, 0.85fr);
    gap: var(--space-xl);
    align-items: center;
    position: relative;
    z-index: 1;
  }

  @include e(hero-logo) {
    color: var(--color-text-primary);
    font-size: 40px;
    margin-bottom: var(--space-m);
  }

  @include e(hero-eyebrow) {
    color: var(--color-accent);
    font-size: var(--font-size-sm);
    font-weight: var(--font-weight-semibold);
    margin: 0 0 var(--space-s);
  }

  @include e(hero-title) {
    font-size: clamp(32px, 5vw, 56px);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
    letter-spacing: -0.02em;
    color: var(--color-text-primary);
    margin-bottom: var(--space-m);
  }

  @include e(hero-subtitle) {
    font-size: var(--font-size-base);
    color: var(--color-text-secondary);
    line-height: var(--line-height-relaxed);
    margin-bottom: var(--space-l);
    max-width: 620px;
  }

  @include e(hero-actions) {
    display: flex;
    align-items: center;
    gap: var(--space-s);
    margin-bottom: var(--space-s);
    flex-wrap: wrap;
  }

  @include e(hero-strip) {
    align-items: center;
    display: flex;
    gap: var(--space-s);
    margin-top: var(--space-l);

    span {
      align-items: center;
      background: var(--color-surface);
      border: 1px solid var(--color-border-light);
      border-radius: 999px;
      box-shadow: var(--shadow-sm);
      color: var(--color-text-secondary);
      display: inline-flex;
      height: 36px;
      justify-content: center;
      width: 36px;
    }
  }

  @include e(signal-panel) {
    box-shadow: var(--shadow-md);
    border-radius: var(--radius-lg);
  }

  @include e(pipeline) {
    padding: 0 0 var(--space-xl);
  }

  @include e(pipeline-content) {
    align-items: start;
    background: var(--color-text-primary);
    border-radius: var(--radius-lg);
    color: var(--color-bg);
    display: grid;
    gap: var(--space-l);
    grid-template-columns: 0.85fr 1.15fr;
    margin: 0 auto;
    max-width: 1120px;
    overflow: hidden;
    padding: var(--space-l);
    position: relative;
    width: calc(100% - (var(--space-l) * 2));

    &::after {
      background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.18), transparent);
      content: '';
      height: 1px;
      left: var(--space-l);
      position: absolute;
      right: var(--space-l);
      top: 0;
    }
  }

  @include e(pipeline-title) {
    color: var(--color-bg);
    font-size: var(--font-size-xl);
    font-weight: var(--font-weight-bold);
    letter-spacing: -0.01em;
    margin: 0 0 var(--space-s);
  }

  @include e(pipeline-subtitle) {
    color: color-mix(in srgb, var(--color-bg), transparent 20%);
    line-height: var(--line-height-relaxed);
    margin: 0;
  }

  @include e(pipeline-points) {
    display: grid;
    gap: var(--space-s);
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }

  @include e(pipeline-point) {
    border: 1px solid color-mix(in srgb, var(--color-bg), transparent 78%);
    border-radius: var(--radius-md);
    padding: var(--space-m);

    strong,
    span {
      display: block;
    }

    strong {
      color: var(--color-bg);
      font-size: var(--font-size-sm);
      margin-bottom: var(--space-xs);
    }

    span {
      color: color-mix(in srgb, var(--color-bg), transparent 24%);
      font-size: var(--font-size-sm);
      line-height: var(--line-height-relaxed);
    }
  }

  @include e(features) {
    padding: var(--space-xl) 0;
  }

  @include e(section-title) {
    font-size: var(--font-size-xl);
    font-weight: var(--font-weight-bold);
    margin-bottom: var(--space-s);
    letter-spacing: -0.01em;
  }

  @include e(section-subtitle) {
    font-size: var(--font-size-base);
    color: var(--color-text-secondary);
    max-width: 460px;
    margin-bottom: var(--space-xl);
    line-height: var(--line-height-relaxed);
  }

  @include e(grid) {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: var(--space-m);
  }

  @include e(card) {
    background: var(--color-surface);
    border-radius: var(--radius-lg);
    border: 1px solid var(--color-border-light);
    color: inherit;
    display: block;
    padding: var(--space-l);
    text-decoration: none;
    box-shadow: var(--shadow-sm);
    transition: border-color var(--transition-fast), box-shadow var(--transition-fast), transform var(--transition-fast);

    &:hover {
      border-color: var(--color-accent);
      box-shadow: var(--shadow-md);
      transform: translateY(-2px);
    }
  }

  @include e(card-icon) {
    color: var(--color-accent);
    display: inline-flex;
    filter: drop-shadow(0 8px 18px color-mix(in srgb, var(--color-accent), transparent 78%));
    margin-bottom: var(--space-m);
  }

  @include e(card-title) {
    font-size: var(--font-size-base);
    font-weight: var(--font-weight-semibold);
    margin-bottom: var(--space-xs);
  }

  @include e(card-desc) {
    font-size: var(--font-size-sm);
    color: var(--color-text-secondary);
    line-height: var(--line-height-relaxed);
  }

  @include e(developer) {
    padding: calc(var(--space-xl) + var(--space-l)) 0 calc(var(--space-xl) + var(--space-l));
    background: #0f1117;
    color: #fff;
  }

  @include e(developer-content) {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-l);
  }

  @include e(developer-title) {
    font-size: var(--font-size-xl);
    font-weight: var(--font-weight-bold);
    color: #fff;
    margin-bottom: var(--space-s);
    letter-spacing: -0.01em;
  }

  @include e(developer-subtitle) {
    font-size: var(--font-size-base);
    color: rgba(255, 255, 255, 0.78);
    max-width: 520px;
    line-height: var(--line-height-relaxed);
    margin-bottom: 0;
  }

  @include e(developer-link) {
    flex: 0 0 auto;
    margin-top: var(--space-xs);
    border-color: rgba(255, 255, 255, 0.28);
    color: #fff;

    &:hover {
      border-color: rgba(255, 255, 255, 0.58);
      color: #fff;
      background: rgba(255, 255, 255, 0.08);
    }
  }

  @include e(cta) {
    padding: var(--space-xl) 0;
    background: var(--color-accent);
    color: #fff;
    margin-top: var(--space-l);
  }

  @include e(cta-title) {
    font-size: var(--font-size-xl);
    font-weight: var(--font-weight-bold);
    color: #fff;
    margin-bottom: var(--space-s);
    letter-spacing: -0.01em;
  }

  @include e(cta-subtitle) {
    font-size: var(--font-size-base);
    color: #fff;
    opacity: 0.85;
    margin-bottom: var(--space-l);
    max-width: 560px;
  }

  @include e(cta-actions) {
    display: flex;
    align-items: center;
    gap: var(--space-s);
    flex-wrap: wrap;

    .landing__btn-pill {
      background: var(--color-accent-dark);
      color: #fff;

      &:hover {
        background: color-mix(in srgb, var(--color-accent-dark), #000 12%);
        color: #fff;
      }
    }

    .landing__btn-outline {
      border-color: rgba(255, 255, 255, 0.3);
      color: rgba(255, 255, 255, 0.9);

      &:hover {
        border-color: rgba(255, 255, 255, 0.6);
        color: #fff;
      }
    }
  }

  @media (max-width: 960px) {
    @include e(grid) {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (max-width: 820px) {
    @include e(hero-layout) {
      grid-template-columns: 1fr;
    }

    @include e(pipeline-content) {
      grid-template-columns: 1fr;
    }

    @include e(pipeline-points) {
      grid-template-columns: 1fr;
    }

    @include e(developer-content) {
      flex-direction: column;
    }
  }

  @media (max-width: 640px) {
    @include e(grid) {
      grid-template-columns: 1fr;
    }
  }

  @media (prefers-reduced-motion: no-preference) {
    @include e(hero) {
      &::before {
        animation: landingSweep 8s ease-in-out infinite;
      }
    }

    @include e(hero-logo) {
      animation: landingRise 520ms ease both;
    }

    @include e(hero-eyebrow) {
      animation: landingRise 560ms ease 80ms both;
    }

    @include e(hero-title) {
      animation: landingRise 620ms ease 140ms both;
    }

    @include e(hero-subtitle) {
      animation: landingRise 660ms ease 200ms both;
    }

    @include e(hero-actions) {
      animation: landingRise 700ms ease 260ms both;
    }

    @include e(hero-strip) {
      animation: landingRise 700ms ease 260ms both;
    }

    @include e(hero-strip) {
      span {
        animation: landingFloat 3.8s ease-in-out infinite;

        &:nth-child(2) { animation-delay: 180ms; }
        &:nth-child(3) { animation-delay: 360ms; }
        &:nth-child(4) { animation-delay: 540ms; }
      }
    }
  }
}

@keyframes landingRise {
  from {
    opacity: 0;
    transform: translateY(10px);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes landingFloat {
  0%,
  100% {
    transform: translateY(0);
  }

  50% {
    transform: translateY(-4px);
  }
}

@keyframes landingSweep {
  0%,
  46% {
    transform: translateX(-65%);
  }

  72%,
  100% {
    transform: translateX(65%);
  }
}
</style>