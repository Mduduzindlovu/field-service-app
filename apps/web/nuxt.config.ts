export default defineNuxtConfig({
  compatibilityDate: '2024-11-01',
  css: ['mapbox-gl/dist/mapbox-gl.css'],
  runtimeConfig: {
    databaseUrl: process.env.DATABASE_URL ?? '',
    public: {
      mapboxToken: process.env.NUXT_PUBLIC_MAPBOX_TOKEN ?? ''
    }
  }
})
