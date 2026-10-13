# Admin panel redesign: shadcn-style theme with Tailwind

Date: 2026-10-07
Status: Phase 1 built; Phase 2 not started

## Goal

Replace the heavy purple admin theme with the shadcn/ui visual language, and
make Tailwind available so custom admin pages are written with utility classes
instead of per-page inline `<style>` blocks. Appearance only: no admin
behaviour, permission, filter or export changes.

## Decisions

- **Stay on ActiveAdmin 3.3.** shadcn/ui is a React component library and
  cannot be used directly in server-rendered ActiveAdmin; the theme reproduces
  its look. Upgrading to ActiveAdmin 4 or replacing ActiveAdmin was rejected as
  too large and risky for a visual change.
- **Neutral zinc palette with Quadroots purple as the accent only** (primary
  button, active sidebar item, links, focus ring). Light theme only.
- **Tailwind via `tailwindcss-rails`** (standalone binary, no Node), loaded in
  the admin panel only. The employee app stays on Bootstrap.
- **Tailwind 3, not 4.** The v4 binaries are published as `linux-gnu`/`musl`
  platform gems, which RubyGems older than 3.3.22 (this project runs 3.3.7 on
  Ruby 3.1.2) cannot install. Revisit when Ruby is upgraded.
- **Two phases**, so the direction can be reviewed before the custom pages are
  rebuilt.

## Architecture

| Piece | Location | Notes |
|---|---|---|
| Design tokens | `:root` in `app/assets/stylesheets/active_admin.scss` | shadcn names (`--background`, `--foreground`, `--muted`, `--border`, `--primary`, ...). Single source of truth. Legacy `--qr-*` names are aliased to them until Phase 2 removes their users. |
| Global theme | `app/assets/stylesheets/active_admin.scss` | Styles every ActiveAdmin-generated screen. Button and field looks are Sass mixins (`button-primary`, `button-outline`, `field`). |
| Tailwind config | `config/tailwind.config.js` | Colours map to the CSS variables above. `important: true` so utilities beat ActiveAdmin's element styles. Preflight is **off**, because the reset would strip the generated screens. Scans `app/admin` and `app/views/admin` only. |
| Tailwind entry | `app/assets/stylesheets/application.tailwind.css` | Adds a scoped reset under `.tw` (box-sizing and border defaults), which custom pages opt in to by wrapping their content in `<div class="tw">`. |
| Build output | `app/assets/builds/tailwind.css` (gitignored) | Built by `tailwindcss:build`, which is hooked into `assets:precompile` and `test:prepare`. In development the Puma plugin in `config/puma.rb` rebuilds on change while `rails server` runs. |
| Registration | `config/initializers/active_admin.rb` | `register_stylesheet 'tailwind.css'`, after `active_admin.css`. |

## Phase 1 (built)

- Tailwind setup as above.
- Global theme rewrite: white sidebar with a soft purple active pill and a
  collapsible Settings group (state kept in `localStorage`), plain title bar,
  hairline tables, primary/outline/destructive buttons, bordered form cards
  with 36px fields and a purple focus ring, restyled filter drawer, scopes,
  pagination, dropdown menus and select2, soft tinted status badges, centred
  login card, stacked form labels on small screens.
- Time Clocks index: the inline-styled state/status spans became `status_tag`s
  so they pick up the badge styling.
- KPI page rebuilt in Tailwind as the reference custom page (filter bar, three
  stat cards, two tables). The `kpi-*` class names are test hooks.

## Phase 2 (not started)

Rebuild the remaining self-styled custom pages in Tailwind to match, removing
their inline `<style>` blocks:

- Dashboard: `app/views/admin/dashboard/*` (super admin dashboard, live state,
  monthly overview)
- Employee profile and timesheet calendar: `app/views/admin/employees/*`
- Time clock detail: `app/views/admin/time_clocks/_show.html.erb`
- Role permission matrix and summary: `app/views/admin/roles/*`
- Task type bulk upload form, Organogram partial
- Remaining inline `style:` attributes in `app/admin/*.rb`
- Then drop the legacy `--qr-*` aliases and the `.calendar-*` colour classes.

## Verification

- Full test suite.
- Headless-Chrome screenshots of login, dashboard, an index, filters open, a
  form, a show page, roles, settings and KPI, at 1440px and 390px wide,
  compared before and after.
