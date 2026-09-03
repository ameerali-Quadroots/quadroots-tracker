# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
# Rails.application.config.assets.precompile += %w( admin.js admin.css )

# The Task Manager module's client side. It is included only by that module's
# pages (app/views/tasks/_head.html.erb) rather than by the global layout, so
# it needs declaring here: sprockets-rails' javascript_include_tag check reads
# config.assets.precompile and does not follow `link` directives in
# manifest.js.
Rails.application.config.assets.precompile += %w[task_manager.js]
