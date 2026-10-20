require "rails_helper"

RSpec.describe "A representation request whose processing fails", type: :request do
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(io: file_fixture("avatar.png").open, filename: "avatar.png", content_type: "image/png")
  end
  let(:path) { rails_representation_path(blob.variant(resize_to_limit: [ 8, 8 ]), only_path: true) }
  let(:placeholder) { %r{/assets/representation-unavailable-\h+\.svg\z} }

  def fail_processing_with(error)
    allow(ActiveStorage.variant_transformer).to receive(:new).and_raise(error)
  end

  it "redirects a permanent cell failure to the placeholder, cacheably" do
    fail_processing_with(HotCell::PermanentFailure.new("unreadable"))
    get path

    expect(response).to have_http_status(:found)
    expect(response.location).to match(placeholder)
    expect(response.headers["Cache-Control"]).to include("max-age=#{100.years.to_i}", "public")
  end

  it "redirects to the placeholder on an asset host too" do
    saved = ActionController::Base.asset_host
    ActionController::Base.asset_host = "https://cdn.example.com"
    fail_processing_with(HotCell::PermanentFailure.new("unreadable"))
    get path

    expect(response).to have_http_status(:found)
    expect(response.location).to start_with("https://cdn.example.com/assets/representation-unavailable-")
  ensure
    ActionController::Base.asset_host = saved
  end

  it "answers a transient cell failure with 503 and no-store" do
    fail_processing_with(HotCell::TransientFailure.new("capacity"))
    get path

    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.headers["Retry-After"]).to eq("5")
  end

  it "treats an in-process Vips::Error the same as a permanent failure" do
    fail_processing_with(Vips::Error.new("decode failed"))
    get path

    expect(response.location).to match(placeholder)
  end

  it "answers 503 no-store when the cell is configured but not listening" do
    Dir.mktmpdir do |root|
      saved = [ HotCell.root, ActiveStorage.variant_transformer ]
      HotCell.root = root
      ActiveStorage.variant_transformer = ActiveStorage::HotCell::Client::Transformers::Image::Vips
      get path

      expect(response).to have_http_status(:service_unavailable)
      expect(response.headers["Cache-Control"]).to eq("no-store")
    ensure
      HotCell.root, ActiveStorage.variant_transformer = saved
    end
  end
end
