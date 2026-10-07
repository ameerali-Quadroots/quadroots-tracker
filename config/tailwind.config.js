// Tailwind is used by the admin panel's custom pages only (the employee app is
// Bootstrap). Colours point at the CSS variables defined in
// app/assets/stylesheets/active_admin.scss, so the SCSS theme and the utility
// classes always agree.
module.exports = {
  content: [
    './app/admin/**/*.rb',
    './app/views/admin/**/*.erb'
  ],
  // Utilities must beat ActiveAdmin's own element styles (table, a, input...).
  important: true,
  // No reset: preflight would strip the styling of every generated ActiveAdmin
  // screen. Custom pages opt in to a small scoped reset with the .tw wrapper.
  corePlugins: { preflight: false },
  theme: {
    extend: {
      colors: {
        background: 'var(--background)',
        page: 'var(--page)',
        foreground: 'var(--foreground)',
        card: 'var(--card)',
        muted: { DEFAULT: 'var(--muted)', foreground: 'var(--muted-foreground)' },
        border: 'var(--border)',
        input: 'var(--input)',
        ring: 'var(--ring)',
        primary: {
          DEFAULT: 'var(--primary)',
          hover: 'var(--primary-hover)',
          foreground: 'var(--primary-foreground)',
          soft: 'var(--primary-soft)',
          'soft-foreground': 'var(--primary-soft-foreground)'
        },
        destructive: { DEFAULT: 'var(--destructive)', soft: 'var(--destructive-soft)' }
      },
      borderRadius: { lg: 'var(--radius)', md: 'var(--radius-sm)' },
      boxShadow: { xs: 'var(--shadow-xs)', card: 'var(--shadow-card)' },
      backgroundImage: {
        // Chevron for native selects (pair with appearance-none bg-no-repeat pr-8).
        chevron: "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%2371717A' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E\")"
      },
      fontFamily: { sans: ['Inter', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'sans-serif'] }
    }
  }
}
