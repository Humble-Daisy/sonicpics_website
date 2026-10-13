# Fork-owned: your product's routes live here. Upstream (modelrails_base)
# freezes this file after creation — add and rewrite routes freely in a fork
# without merge conflicts on config/routes.rb. See /docs/developer/forking.

# Static pages are one resource, shown by name: the constraint keeps the URLs
# at the top level, and the templates under app/views/pages are the allowlist
# (PagesController::PAGES). Add a page by adding its template, its name here,
# and its name to PAGES.
root to: "pages#show", defaults: { id: "home" }
resources :pages, only: :show, path: "", constraints: { id: /about|privacy|contact|support|sample_uses/ }
