# Pin npm packages by running ./bin/importmap

pin "application"
pin "navigation_focus"
pin "lexxy_label_in_name"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# Shared overlay primitives (top layer, dismissal stack) — plain ES modules rather
# than controllers, because the dismissal stack must be a single instance shared by
# every overlay controller.
pin_all_from "app/javascript/overlays", under: "overlays"
# Vendored third-party scoring (cmdk's command-score, MIT — see the file header).
pin_all_from "app/javascript/search", under: "search"
# Shared menu-family movement (modelrails_ui v0.14.0) — menu/menubar/combobox/command
# import it by bare specifier; without this pin all four throw on connect.
pin_all_from "app/javascript/keyboard", under: "keyboard"
pin "lexxy", to: "lexxy.js"
# Vendored (SEC-6): the self-contained dist bundle, committed at an exact
# version so production script-src carries no CDN host and the bytes can't
# change under a floating tag. Upgrade = download the new
# cropperjs@X.Y.Z/dist/cropper.esm.js into vendor/javascript/cropperjs.js
# and commit the diff.
pin "cropperjs" # @2.1.1

# Chart.js is opt-in (the gem doesn't bundle it; chart_controller.js lazy-imports it).
# Pinned in development only so the Lookbook catalog can render the chart component —
# this app uses chart solely in the dev-only catalog, so production stays lean and
# downstream apps still opt in themselves.
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4/+esm" if Rails.env.development?

# Lexxy's uploader dynamic-imports @rails/activestorage; without this pin the
# import fails to resolve and editor attachments silently never upload. Ships
# from the activestorage gem's own asset path — local, never a CDN (SEC-7).
pin "@rails/activestorage", to: "activestorage.esm.js"
