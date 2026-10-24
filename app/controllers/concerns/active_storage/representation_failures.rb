# A variant that fails to process answers its image request instead of raising: permanent failures redirect to a
# placeholder that may be cached, transient ones 503 with no-store so the next view fetches again. /docs/developer/security
module ActiveStorage::RepresentationFailures
  extend ActiveSupport::Concern

  included do
    rescue_from "HotCell::PermanentFailure", "Vips::Error", with: :representation_unavailable
    rescue_from "HotCell::TransientFailure", with: :representation_pending
  end

  private
    def representation_unavailable
      expires_in 100.years, public: true
      redirect_to helpers.asset_path("representation-unavailable.svg"), allow_other_host: true
    end

    def representation_pending
      response.headers["Cache-Control"] = "no-store"
      response.headers["Retry-After"] = "5"
      head :service_unavailable
    end
end
