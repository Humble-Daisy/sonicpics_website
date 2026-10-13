# Static pages as one resource, keyed by name. The templates under
# app/views/pages are the allowlist; the route constraint in
# config/routes/app.rb is the first fence and PAGES the second.
class PagesController < ApplicationController
  allow_unauthenticated_access

  PAGES = %w[home about privacy contact support sample_uses].freeze

  def show
    raise ActionController::RoutingError, "No page #{params[:id].inspect}" unless PAGES.include?(params[:id])

    render params[:id]
  end
end
