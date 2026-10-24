# Static pages as one resource, keyed by name. The templates under
# app/views/pages are the allowlist; the route constraint in
# config/routes/app.rb is the first fence and PAGES the second.
class PagesController < ApplicationController
  allow_unauthenticated_access

  # Visitors get the brochure (layouts/pages). A signed-in user keeps the app
  # chrome, since the brochure links nowhere into the app.
  layout -> { authenticated? ? "application" : "pages" }

  PAGES = %w[home about privacy contact support sample_uses].freeze

  def show
    raise ActionController::RoutingError, "No page #{params[:id].inspect}" unless PAGES.include?(params[:id])

    render params[:id]
  end
end
