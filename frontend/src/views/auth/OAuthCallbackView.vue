<template>
  <div class="min-h-screen bg-gray-50 px-4 py-10 dark:bg-dark-900">
    <div class="mx-auto max-w-2xl">
      <div class="card p-6">
        <!-- Success state -->
        <div v-if="code && !error">
          <div class="mb-4 flex items-center gap-3">
            <div class="flex h-10 w-10 items-center justify-center rounded-full bg-green-100 dark:bg-green-900/40">
              <svg class="h-6 w-6 text-green-600 dark:text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <div>
              <h1 class="text-lg font-semibold text-gray-900 dark:text-white">{{ t('auth.oauth.successTitle') }}</h1>
              <p class="text-sm text-gray-500 dark:text-gray-400">{{ t('auth.oauth.successDesc') }}</p>
            </div>
          </div>

          <!-- Instruction banner -->
          <div class="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-3 dark:border-blue-700 dark:bg-blue-900/30">
            <p class="text-sm text-blue-800 dark:text-blue-300">
              {{ t('auth.oauth.pasteInstruction') }}
            </p>
          </div>
        </div>

        <!-- Error state -->
        <div v-else-if="error" class="mb-4">
          <h1 class="text-lg font-semibold text-red-700 dark:text-red-400">{{ t('auth.oauth.errorTitle') }}</h1>
          <div class="mt-2 rounded-lg border border-red-200 bg-red-50 p-3 dark:border-red-700 dark:bg-red-900/30">
            <p class="text-sm text-red-600 dark:text-red-400">{{ error }}</p>
          </div>
        </div>

        <!-- No params state -->
        <div v-else class="mb-4">
          <h1 class="text-lg font-semibold text-gray-900 dark:text-white">OAuth Callback</h1>
          <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            {{ t('auth.oauth.waitingDesc') }}
          </p>
        </div>

        <div v-if="code || fullUrl" class="space-y-4">
          <!-- Full URL - primary action -->
          <div>
            <label class="input-label">{{ t('auth.oauth.fullUrl') }}</label>
            <div class="flex gap-2">
              <input class="input flex-1 font-mono text-xs" :value="fullUrl" readonly />
              <button
                class="btn btn-primary shrink-0"
                type="button"
                :disabled="!fullUrl"
                @click="copy(fullUrl)"
              >
                {{ t('auth.oauth.copy') }}
              </button>
            </div>
            <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">{{ t('auth.oauth.fullUrlHint') }}</p>
          </div>

          <div class="border-t border-gray-200 pt-3 dark:border-dark-600">
            <p class="mb-3 text-xs text-gray-500 dark:text-gray-400">{{ t('auth.oauth.orCopyParts') }}</p>
            <div class="space-y-3">
              <div>
                <label class="input-label">{{ t('auth.oauth.code') }}</label>
                <div class="flex gap-2">
                  <input class="input flex-1 font-mono text-sm" :value="code" readonly />
                  <button class="btn btn-secondary" type="button" :disabled="!code" @click="copy(code)">
                    {{ t('auth.oauth.copy') }}
                  </button>
                </div>
              </div>

              <div>
                <label class="input-label">{{ t('auth.oauth.state') }}</label>
                <div class="flex gap-2">
                  <input class="input flex-1 font-mono text-sm" :value="state" readonly />
                  <button
                    class="btn btn-secondary"
                    type="button"
                    :disabled="!state"
                    @click="copy(state)"
                  >
                    {{ t('auth.oauth.copy') }}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { useClipboard } from '@/composables/useClipboard'

const route = useRoute()
const { t } = useI18n()
const { copyToClipboard } = useClipboard()

const code = computed(() => (route.query.code as string) || '')
const state = computed(() => (route.query.state as string) || '')
const error = computed(
  () => (route.query.error as string) || (route.query.error_description as string) || ''
)

const fullUrl = computed(() => {
  if (typeof window === 'undefined') return ''
  return window.location.href
})

const copy = (value: string) => {
  if (!value) return
  copyToClipboard(value, 'Copied')
}
</script>
