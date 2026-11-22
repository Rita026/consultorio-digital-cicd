// Configuración global para pruebas unitarias (Vitest + jsdom).
// jsdom no implementa window.matchMedia, que usan ThemeService y
// AccessibilityService; se agrega una versión simulada.
if (typeof window !== 'undefined' && !window.matchMedia) {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: (query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: () => {},
      removeEventListener: () => {},
      dispatchEvent: () => false,
    }),
  });
}
