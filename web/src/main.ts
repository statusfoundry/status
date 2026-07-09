import '@sil/ui/styles'
import './styles/index.scss'

import { createApp } from 'vue'
import { createRouter, createWebHistory } from 'vue-router'

import App from './App.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: () => import('./views/HomeView.vue') },
    { path: '/download/', component: () => import('./views/DownloadView.vue') },
    { path: '/plugins/', component: () => import('./views/PluginsView.vue') },
    { path: '/plugins/:pluginId/', component: () => import('./views/PluginDetailView.vue') },
    { path: '/publishers/:publisherId/', component: () => import('./views/PublisherDetailView.vue') },
    { path: '/developers/', component: () => import('./views/DevelopersView.vue') },
    { path: '/docs/', component: () => import('./views/DocsView.vue') },
    { path: '/docs/:docSlug/', component: () => import('./views/DocDetailView.vue') },
    { path: '/privacy/', component: () => import('./views/PrivacyView.vue') },
    { path: '/changelog/', component: () => import('./views/ChangelogView.vue') },
  ],
  scrollBehavior(_to, _from, savedPosition) {
    if (savedPosition) {
      return savedPosition
    }

    return new Promise((resolve) => {
      requestAnimationFrame(() => {
        resolve({ top: 0, left: 0 })
      })
    })
  },
})

router.afterEach((to, from) => {
  if (to.fullPath === from.fullPath) {
    return
  }

  window.scrollTo({ top: 0, left: 0 })
})

createApp(App).use(router).mount('#app')
