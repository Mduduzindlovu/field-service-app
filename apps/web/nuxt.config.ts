export default defineNuxtConfig({
  compatibilityDate: '2024-11-01',
  runtimeConfig: {
    databaseUrl: process.env.DATABASE_URL ?? '',
    public: {
      mapboxToken: process.env.NUXT_PUBLIC_MAPBOX_TOKEN ?? ''
    }
  }
})
