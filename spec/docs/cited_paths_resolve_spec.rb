require "rails_helper"

# A doc that cites a path that does not exist is a false statement a reader
# cannot see; absent-by-design citations sit in the allow-list with a reason.
RSpec.describe "Documentation cited paths" do
  let(:docs_root) { Rails.root.join("app/docs") }
  let(:citation) { %r{`((?:app|config|lib|spec|bin|db)/[^`\s]+)`} }
  let(:allowed_absent) do
    {
      "config/initializers/session_store.rb" => "optional; a fork adds it only to share a cookie domain",
      "config/markdowndocs_categories.local.yml" => "fork-owned; the template ships none",
      "app/docs/my-feature.md" => "a placeholder name in the forking guide's example",
      "app/models/concerns/noticed/deliverable.rb" => "inside the noticed 3.0.0 gem, named beside it",
      "app/models/ssrf_protection.rb" => "Fizzy's file, cited as the port source for #658",
      "app/models/webhook/delivery.rb" => "Fizzy's file, the caller of that port source",
      "config/credentials.yml.enc" => "the template ships none; a fork generates and commits its own",
      "config/master.key" => "gitignored; every checkout keeps its own",
      "config/credentials/production.key" => "gitignored; a deployment keeps its own",
      "config/credentials/staging.yml.enc" => "the template ships none; a fork with staging commits its own",
      "app/assets/builds/tailwind.css" => "a build artifact; tailwindcss:build writes it"
    }
  end

  let(:citations) do
    Dir[docs_root.join("**/*.md")].sort.flat_map do |file|
      File.foreach(file).with_index(1).flat_map do |line, number|
        line.scan(citation).filter_map do |(cited)|
          path = cited.sub(/:[\d,-]+\z/, "")
          next if path.match?(/[*<{]/)

          [ path, "#{Pathname(file).relative_path_from(Rails.root)}:#{number}" ]
        end
      end
    end
  end

  let(:cited_paths) { citations.map(&:first).uniq }

  it "cites only tracked paths, or paths allowed absent with a reason" do
    absent = citations.reject { |path, _| allowed_absent.key?(path) || tracked_path?(path) }
    expect(absent).to be_empty, absent.map { |path, at|
      "#{at} cites #{path}, which is not in the repo — repoint it, or add it to allowed_absent with a reason"
    }.join("\n")
  end

  it "keeps the allow-list honest: every allowed-absent path is still absent" do
    stale = allowed_absent.keys.select { |path| tracked_path?(path) }
    expect(stale).to be_empty, "Now tracked, remove from allowed_absent: #{stale.join(', ')}"
  end

  it "keeps the allow-list honest: every allowed-absent path is still cited" do
    dead = allowed_absent.keys - cited_paths
    expect(dead).to be_empty, "No longer cited, remove from allowed_absent: #{dead.join(', ')}"
  end
end
