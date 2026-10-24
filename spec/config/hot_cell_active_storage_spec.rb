require "rails_helper"

# Active Storage through a real Hot Cell spawned as its own process (a cell forked from a process that has run
# libvips crashes on Linux): every allowed image type thumbnails and analyzes there, and failures are classified.
RSpec.describe "Active Storage through a Hot Cell" do
  fixtures = {
    "image/png" => "sample.png", "image/jpeg" => "sample.jpg", "image/gif" => "sample.gif",
    "image/webp" => "sample.webp", "image/heic" => "sample.heic", "image/heif" => "sample.heif"
  }

  def spawn_cell(root)
    directory = File.join(root, "active_storage")
    log = File.join(root, "cell.log")
    pid = Process.spawn({ "HOTCELL_DIR" => directory,
                          "HOTCELL_CONFIG" => Rails.root.join("hotcell/config.rb").to_s,
                          "HOTCELL_OPERATIONS" => Rails.root.join("hotcell/operations").to_s },
                        "bundle", "exec", "hotcell", "--development", out: log, err: log, chdir: Rails.root.to_s)
    give_up = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    until File.socket?(File.join(directory, "work.sock")) && File.socket?(File.join(directory, "control.sock"))
      exited = Process.waitpid(pid, Process::WNOHANG)
      raise "the cell did not boot:\n#{File.read(log)}" if exited || Process.clock_gettime(Process::CLOCK_MONOTONIC) > give_up
      sleep 0.05
    end
    pid
  end

  def upload(name, content_type)
    ActiveStorage::Blob.create_and_upload!(io: Rails.root.join("spec/fixtures/files/hotcell", name).open,
                                           filename: name, content_type: content_type)
  end

  def thumbnail(blob) = blob.variant(resize_to_limit: [ 8, 8 ]).processed

  def cell_operations
    performed = []
    subscriber = ActiveSupport::Notifications.subscribe("perform.hot_cell") { |*, payload| performed << payload[:operation] }
    yield
    performed
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  before(:all) do
    Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/hotcell/sample.png").to_s).thumbnail_image(8).write_to_buffer(".png")
    @root = Dir.mktmpdir("hotcell", "/tmp")
    @pid = spawn_cell(@root)
    @saved = [ HotCell.root, ActiveStorage.variant_transformer, ActiveStorage.analyzers ]
    HotCell.root = @root
    ActiveStorage.variant_transformer = ActiveStorage::HotCell::Client::Transformers::Image::Vips
    ActiveStorage.analyzers = [ ActiveStorage::HotCell::Client::Analyzers::Image::Vips ]
  end

  after(:all) do
    HotCell.root, ActiveStorage.variant_transformer, ActiveStorage.analyzers = @saved
    Process.kill(:TERM, @pid)
    Process.wait(@pid)
    FileUtils.rm_rf(@root)
  end

  it "covers every allowed image type" do
    expect(fixtures.keys).to match_array(ApplicationRecord::IMAGE_CONTENT_TYPES)
  end

  fixtures.each do |content_type, name|
    it "thumbnails #{content_type} through the cell" do
      blob = upload(name, content_type)
      variant = nil

      expect(cell_operations { variant = thumbnail(blob) }).to include("active_storage.transformers.image.vips")
      expect(variant.image.download.bytesize).to be > 0
    end
  end

  it "records width and height through the cell" do
    blob = upload("sample.png", "image/png")

    expect(cell_operations { blob.analyze }).to include("active_storage.analyzers.image.vips")
    expect(blob.metadata.slice("width", "height")).to eq("width" => 16, "height" => 16)
  end

  it "classifies broken bytes as a permanent failure" do
    expect { thumbnail(upload("truncated.png", "image/png")) }.to raise_error(HotCell::PermanentFailure)
  end

  it "classifies an unreachable cell as a transient failure" do
    Dir.mktmpdir("hotcell", "/tmp") do |nobody_listening|
      HotCell.root = nobody_listening

      expect { thumbnail(upload("sample.png", "image/png")) }.to raise_error(HotCell::TransientFailure)
    ensure
      HotCell.root = @root
    end
  end
end
