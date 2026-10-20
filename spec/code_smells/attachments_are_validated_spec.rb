require "rails_helper"

# Every upload is gated by type and size, and nothing decodes it in the app process to validate it.
# Rich-text direct uploads are gated in DirectUploadsController instead. See /docs/developer/testing.
RSpec.describe "Code smell: attachments are validated" do
  decoding_validators = %i[dimension aspect_ratio processable_file]

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

  validations = lambda do |source, name|
    calls.call(source).select { |call| call.name == :validates && call.receiver.nil? && first_symbol.call(call) == name }.flat_map do |call|
      call.arguments.arguments.grep(Prism::KeywordHashNode).flat_map do |hash|
        hash.elements.filter_map { |pair| pair.key.unescaped.to_sym if pair.respond_to?(:key) && pair.key.is_a?(Prism::SymbolNode) }
      end
    end
  end

  unvalidated = lambda do |files|
    attachments.call(files)
      .reject { |a| (%i[content_type size] - validations.call(files.fetch(a[:file]), a[:name])).empty? }
      .map { |a| "#{a[:file]}##{a[:name]}" }
  end

  decoding = lambda do |files|
    attachments.call(files).flat_map do |a|
      (validations.call(files.fetch(a[:file]), a[:name]) & decoding_validators).map { |validator| "#{a[:file]}##{a[:name]} #{validator}" }
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
end
