require "rails_helper"
require "open3"

RSpec.describe "config/initializers/hotcell.rb" do
  def boot(env)
    Open3.capture2e({ "RAILS_ENV" => "test", "SKIP_COVERAGE" => "1" }.merge(env), "bin/rails", "runner",
      'puts [ActiveStorage.variant_transformer.name, ActiveStorage.analyzers.map(&:name).join(","), ActiveStorage.previewers.size].join("|")',
      chdir: Rails.root.to_s)
  end

  it "leaves Active Storage stock when HOTCELL_ROOT is unset" do
    expect(ENV["HOTCELL_ROOT"]).to be_nil
    expect(ActiveStorage.variant_transformer).to eq(ActiveStorage::Transformers::Vips)
    expect(ActiveStorage.analyzers).to include(ActiveStorage::Analyzer::ImageAnalyzer::Vips)
    expect(ActiveStorage.previewers.size).to eq(3)
  end

  it "routes variants and analysis to the cell and turns previewers off when HOTCELL_ROOT is set" do
    out, status = boot("HOTCELL_ROOT" => "/nonexistent/hotcell")

    expect(status).to be_success, out
    expect(out.lines.last.strip).to eq(
      "ActiveStorage::HotCell::Client::Transformers::Image::Vips|ActiveStorage::HotCell::Client::Analyzers::Image::Vips|0"
    )
  end

  it "treats an empty HOTCELL_ROOT as unset" do
    out, status = boot("HOTCELL_ROOT" => "")

    expect(status).to be_success, out
    expect(out.lines.last.strip).to start_with("ActiveStorage::Transformers::Vips|")
  end

  it "boots with an empty HOTCELL_GROUP" do
    out, status = boot("HOTCELL_GROUP" => "")

    expect(status).to be_success, out
  end

  it "refuses a non-numeric HOTCELL_GROUP at boot" do
    out, status = boot("HOTCELL_ROOT" => "/nonexistent/hotcell", "HOTCELL_GROUP" => "abc")

    expect(status).not_to be_success
    expect(out).to include("must be a numeric gid")
  end
end
