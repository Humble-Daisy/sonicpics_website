Rails.application.config.to_prepare do
  ActiveStorage::Representations::BaseController.include ActiveStorage::RepresentationFailures
end
