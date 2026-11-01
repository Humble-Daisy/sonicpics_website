require "rails_helper"

RSpec.describe "OAuth credentials examples" do
  let(:dug_paths) do
    Rails.root.join("config/initializers/omniauth.rb").read
      .scan(/credentials\.dig\(([^)]+)\)/).map { |(args)| args.scan(/:(\w+)/).flatten.map(&:to_sym) }
  end

  it "reads the paths it checks from the initializer" do
    expect(dug_paths).to include(%i[oauth google client_id], %i[oauth github client_secret])
  end

  %w[README.md app/docs/developer/getting-started.md].each do |doc|
    it "#{doc} shows every credentials path the OmniAuth initializer reads" do
      example = Rails.root.join(doc).read.scan(/```yaml\n(.*?)```/m).flatten.find { |block| block.include?("client_id") }
      credentials = YAML.safe_load(example.to_s).to_h.deep_symbolize_keys

      missing = dug_paths.reject { |path| credentials.dig(*path).present? }
      expect(missing).to be_empty, "#{doc}'s example lacks #{missing.map { |path| path.join('.') }.join(', ')}"
    end
  end
end
