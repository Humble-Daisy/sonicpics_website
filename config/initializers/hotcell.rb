# Off until HOTCELL_ROOT is set: then variants and image analysis run in the sandboxed cell, and nothing
# previews in this process. See /docs/developer/hot-cell.
HotCell.root = ENV["HOTCELL_ROOT"].presence
HotCell.group = ENV["HOTCELL_GROUP"].presence
cell = HotCell.register "active_storage", timeout: 30

if cell.enabled?
  Rails.application.config.active_storage.variant_processor = ActiveStorage::HotCell::Client::Transformers::Image::Vips
  Rails.application.config.active_storage.analyzers = [ ActiveStorage::HotCell::Client::Analyzers::Image::Vips ]
  Rails.application.config.active_storage.previewers = []
end

Rails.application.config.after_initialize { HotCell.describe_cells }
