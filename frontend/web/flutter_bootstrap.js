{{flutter_js}}
{{flutter_build_config}}

// Disable Flutter engine external font fallback CDN. Bundled Noto fonts in
// pubspec.yaml cover Thai and Latin/CJK scripts for language menu labels.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      fontFallbackBaseUrl: '',
    });
    await appRunner.runApp();
  },
});
