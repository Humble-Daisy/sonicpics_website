require "rails_helper"

# Every upload is gated by type and size, and only validators known to leave its bytes alone may check it.
# Rich-text direct uploads are gated in DirectUploadsController instead. See /docs/developer/testing.
RSpec.describe "Code smell: attachments are validated" do
  reads_nothing = %i[content_type size total_size limit attached presence]

  sources = lambda do
    Dir[Rails.root.join("app/models/**/*.rb")].sort.to_h { |file| [ file.delete_prefix("#{Rails.root}/"), File.read(file) ] }
  end

  calls = lambda do |source|
    stack = [ Prism.parse(source).value ]
    found = []
    while (node = stack.pop)
      found << node if node.is_a?(Prism::CallNode)
      stack.concat(node.compact_child_nodes)
    end
    found
  end

  first_symbol = lambda do |call|
    argument = call.arguments&.arguments&.first
    argument.unescaped.to_sym if argument.is_a?(Prism::SymbolNode)
  end

  attachments = lambda do |files|
    files.flat_map do |file, source|
      calls.call(source)
        .select { |call| %i[has_one_attached has_many_attached].include?(call.name) && first_symbol.call(call) }
        .map { |call| { file: file, name: first_symbol.call(call) } }
    end
  end

  symbol_pairs = lambda do |elements|
    elements.select { |pair| pair.respond_to?(:key) && pair.key.is_a?(Prism::SymbolNode) }
  end

  options = lambda do |source, name|
    calls.call(source).select { |call| call.name == :validates && call.receiver.nil? && first_symbol.call(call) == name }.flat_map do |call|
      call.arguments.arguments.grep(Prism::KeywordHashNode).flat_map { |hash| symbol_pairs.call(hash.elements) }
    end
  end

  validations = ->(source, name) { options.call(source, name).map { |pair| pair.key.unescaped.to_sym } }

  spoofing_protected = lambda do |pair|
    pair.key.unescaped == "content_type" && pair.value.is_a?(Prism::HashNode) &&
      symbol_pairs.call(pair.value.elements).any? { |option| option.key.unescaped == "spoofing_protection" }
  end

  unvalidated = lambda do |files|
    attachments.call(files)
      .reject { |a| (%i[content_type size] - validations.call(files.fetch(a[:file]), a[:name])).empty? }
      .map { |a| "#{a[:file]}##{a[:name]}" }
  end

  decoding = lambda do |files|
    attachments.call(files).flat_map do |a|
      found = options.call(files.fetch(a[:file]), a[:name])
      unknown = found.map { |pair| pair.key.unescaped.to_sym } - reads_nothing
      spoofing = found.select { |pair| spoofing_protected.call(pair) }.map { "content_type spoofing_protection" }
      (unknown.map(&:to_s) + spoofing).map { |validator| "#{a[:file]}##{a[:name]} #{validator}" }
    end
  end

  it "finds the attachments it was written against" do
    expect(attachments.call(sources.call).map { |a| "#{a[:file]}##{a[:name]}" }).to match_array(%w[
      app/models/project.rb#logo app/models/user/avatar.rb#avatar app/models/user/avatar.rb#avatar_original
      app/models/workspace/branding.rb#logo app/models/workspace/branding.rb#logo_original
    ])
  end

  it "validates content type and size on every attachment" do
    missing = unvalidated.call(sources.call)

    expect(missing).to be_empty,
      "These attachments lack a content_type: or size: validation:\n  #{missing.join("\n  ")}\n" \
      "fix: `validates :name, content_type: ApplicationRecord::IMAGE_CONTENT_TYPES, size: { less_than: 5.megabytes }`\n" \
      "rule: /docs/developer/testing (Attachments are validated). Rich-text direct uploads are gated in " \
      "DirectUploadsController, not here."
  end

  it "decodes no upload in the app process to validate it" do
    found = decoding.call(sources.call)

    expect(found).to be_empty,
      "These validations decode the upload with libvips in the app process:\n  #{found.join("\n  ")}\n" \
      "rule: /docs/developer/testing (Attachments are validated)"
  end

  it "catches an attachment with no validation, including the block form" do
    planted = sources.call.merge("app/models/x.rb" => <<~RUBY)
      class X < ApplicationRecord
        has_one_attached :photo do |attachable|
          attachable.variant :thumb, resize_to_limit: [ 100, 100 ]
        end
      end
    RUBY

    expect(unvalidated.call(planted)).to eq([ "app/models/x.rb#photo" ])
  end

  it "catches a decoding validator" do
    planted = sources.call.merge("app/models/x.rb" => <<~RUBY)
      class X < ApplicationRecord
        has_one_attached :photo
        validates :photo, content_type: %w[image/png], size: { less_than: 1.megabyte }, dimension: { width: 10 }
      end
    RUBY

    expect(decoding.call(planted)).to eq([ "app/models/x.rb#photo dimension" ])
  end

  it "catches any validator it does not know to leave the bytes alone" do
    planted = sources.call.merge("app/models/x.rb" => <<~RUBY)
      class X < ApplicationRecord
        has_one_attached :photo
        validates :photo, content_type: %w[application/pdf], size: { less_than: 1.megabyte }, pages: { max: 10 }
      end
    RUBY

    expect(decoding.call(planted)).to eq([ "app/models/x.rb#photo pages" ])
  end

  it "catches content-type spoofing protection, which reads the upload" do
    planted = sources.call.merge("app/models/x.rb" => <<~RUBY)
      class X < ApplicationRecord
        has_one_attached :photo
        validates :photo, content_type: { in: %w[image/png], spoofing_protection: true }, size: { less_than: 1.megabyte }
      end
    RUBY

    expect(decoding.call(planted)).to eq([ "app/models/x.rb#photo content_type spoofing_protection" ])
  end
end
