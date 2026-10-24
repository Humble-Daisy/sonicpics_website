require "rails_helper"

# The i18n gem skips interpolation when a call passes no values, so an unknown
# %{token} leaks raw to the user, and `check-consistent-interpolations` cannot
# see it — it compares locales, and there is one. This spec is that gate:
# every token in every value is a vocabulary token (supplied by the backend
# hook) or a caller argument this list knows about. Adding a caller argument
# means adding it here, with the call site that supplies it.
RSpec.describe "Code smell: every locale interpolation token is supplied" do
  caller_supplied = %w[
    accepter action added_user_name address app_name cap count current date
    decliner_email device duration email first_name from hours_remaining initials
    invitee_email inviter limit link max member metric minutes mode name
    names new_email new_role nickname os percent period phrase project_name
    provider query relative role sender sent shown skipped summary time title to
    user_name workspace_name zone
  ]
  # Non-vocabulary tokens a caller supplies; `count` and `name` come from JavaScript.
  js_filled_keys = %w[form_draft.restored_other identity_picker.js.color_announce]

  def tokens_in(path)
    File.readlines(path).each_with_index.flat_map do |line, index|
      next [] if line.match?(/\A\s*#/)
      line.scan(/%\{([A-Za-z_]+)\}/).flatten.map { |token| [ token, "#{path.basename}:#{index + 1}" ] }
    end
  end

  it "knows where every %{token} comes from" do
    known = caller_supplied + Vocabulary.tokens.keys.map(&:to_s)
    unknown = Dir.glob(Rails.root.join("config/locales/en/*.yml"))
      .flat_map { |f| tokens_in(Pathname.new(f)) }
      .reject { |token, _| known.include?(token) }
      .map { |token, location| "#{location}  %{#{token}}" }

    expect(unknown).to be_empty,
      "A %{token} in a locale value that nothing fills. The i18n gem skips interpolation on a " \
      "value-less call, so the user sees the braces (\"Hello %{nobody}\"). Fix: a caller supplies " \
      "it → add the name to caller_supplied in this spec, beside the call site; it is the " \
      "product's noun → write a vocabulary placeholder (%{project}, %{Workspace}…). " \
      "Read: /docs/developer/i18n (Vocabulary).\n  #{unknown.join("\n  ")}"
  end

  it "reports a planted unknown token" do
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("probe.en.yml")
      path.write(%(en:\n  probe: "Hello %{nobody}"\n))

      expect(tokens_in(path)).to contain_exactly([ "nobody", "probe.en.yml:2" ])
    end
  end

  # config/initializers/vocabulary.rb documents that a string carrying BOTH a
  # noun token and a JS-filled placeholder raises on a value-less call: the
  # hook sees the noun token, merges Vocabulary.tokens in, and the JS-filled
  # placeholder (%{count}, %{name}) is left missing (#1111). Walking the
  # public `translations` tree, not `I18n.t`, so checking this never itself
  # triggers the raise it guards against.
  def resolved_value(key)
    key.split(".").inject(I18n.backend.translations.fetch(:en)) { |node, part| node[part.to_sym] }
  end

  it "keeps a JS-filled key's value free of a vocabulary token" do
    vocabulary_pattern = /%\{(#{Vocabulary.tokens.keys.join("|")})\}/
    offenders = js_filled_keys.select { |key| resolved_value(key).to_s.match?(vocabulary_pattern) }

    expect(offenders).to be_empty,
      "A key JavaScript fills also carries a vocabulary placeholder. The hook sees the placeholder, " \
      "merges the nouns in, and the i18n gem raises on the still-missing %{count}/%{name} at every " \
      "value-less call — a 500 on that page (#1111). Fix: keep JS-filled strings free of noun " \
      "placeholders, or drop the key from js_filled_keys if Ruby now supplies the value. " \
      "Read: /docs/developer/i18n (Vocabulary): #{offenders.join(', ')}"
  end

  # A caller that passes `workspace:` or `project:` to a translation is naming
  # the noun's slot with a record's name — the homonym that rendered "Join
  # course" in a spike and doubled a project's name in this branch. Names are
  # %{workspace_name} / %{project_name}; the noun tokens are the backend's.
  def offending_calls_in(path)
    call = /(?:\bt|I18n\.t|translate)\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)/m
    vocabulary_names = Vocabulary.tokens.keys.join("|")
    label = path.to_s.start_with?(Rails.root.to_s) ? path.relative_path_from(Rails.root) : path.basename
    File.read(path).scan(call).filter_map do |text|
      next unless text.match?(/\b(#{vocabulary_names}):\s/)
      "#{label}  #{text.lines.first.strip[0, 80]}"
    end
  end

  it "never lets a caller pass a vocabulary token name as a translation argument" do
    offenders = Dir.glob(Rails.root.join("app/**/*.{rb,erb}"))
      .map { |f| Pathname.new(f) }
      .flat_map { |p| offending_calls_in(p) }

    expect(offenders).to be_empty,
      "A translation call passes a vocabulary placeholder's name (workspace:, project:) as an " \
      "argument. That slot is the product's noun and the backend fills it; a record's name passed " \
      "there renders \"Join course\" with the name gone, or doubles it. Fix: pass " \
      "workspace_name:/project_name: and write %{workspace_name} in the string. " \
      "Read: /docs/developer/i18n (Vocabulary).\n  #{offenders.join("\n  ")}"
  end

  it "reports a planted call that passes a vocabulary token name" do
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("probe.rb")
      path.write(%(t("invitations.join", workspace: workspace.name)\n))

      expect(offending_calls_in(path)).to contain_exactly(a_string_starting_with("probe.rb"))
    end
  end
end
