require "rails_helper"
require "yaml"

# Six locale keys rendered `translation missing` to real users while their
# request specs passed, because those specs asserted `redirect_to(...)` and
# never the message (#521). A redirect-only assertion walks the path but proves
# nothing about what the user reads, so copy can be wrong, empty, or the wrong
# key entirely and stay green.
#
# The project's other two i18n gates do not close this:
#   * `raise_on_missing_translations` fires only when a spec walks the path AND
#     the call site carries no inline `default:`.
#   * `i18n-tasks missing` covers EXISTENCE.
# Neither covers *selection of the right key* — which is the whole game when two
# branches redirect to the same place. Adding these assertions immediately found
# one: the already-accepted invitation path is caught by `find_valid_invitation`
# (`expired_or_used`), not the `NotAcceptable` rescue (`acceptance_failed`). Both
# redirect to root, so only the message tells them apart.
RSpec.describe "Flash messages are asserted, not just redirects" do
  def locale_values
    Dir.glob(Rails.root.join("config/locales/en/**/*.yml")).each_with_object({}) do |file, values|
      data = YAML.safe_load_file(file, aliases: true)
      next unless data.is_a?(Hash)

      flatten_locale(data, "", values)
    rescue Psych::Exception
      next
    end
  end

  def flatten_locale(hash, prefix, values)
    hash.each do |key, value|
      path = prefix.empty? ? key : "#{prefix}.#{key}"
      if value.is_a?(Hash)
        flatten_locale(value, path, values)
      else
        values[path.sub(/\Aen\./, "")] = value.to_s
      end
    end
  end

  # Three spellings, including a `notice = t(...)` local handed to redirect_to and a `notice +=` suffix.
  def flash_expression(line)
    if line =~ /(?:notice|alert):\s*(.+)/
      Regexp.last_match(1)
    elsif line =~ /(?:flash(?:\.now)?\[:(?:notice|alert)\]|\b(?:notice|alert))\s*\+?=(?!=)\s*(.+)/
      Regexp.last_match(1)
    end
  end

  # Every `t()` key in the expression; a lazy `t(".key")` resolves against its controller and action.
  def flash_keys(expression, controller, action)
    expression.scan(/\bt\(\s*"(\.?)([a-z_.]+)"/).map do |lazy, key|
      lazy.empty? ? key : "#{controller.tr('/', '.')}.#{action}.#{key}"
    end
  end

  def flashes_in(source, path)
    controller = path.split("app/controllers/").last.sub("_controller.rb", "")
    action = nil

    source.lines.each_with_index.filter_map do |line, index|
      action = Regexp.last_match(1) if line =~ /\A\s*def\s+([a-z_]+)/
      next if line.strip.start_with?("#")

      expression = flash_expression(line) or next
      { at: "#{path}:#{index + 1}", expression: expression.strip.delete_suffix("}").strip,
        keys: flash_keys(expression, controller, action) }
    end
  end

  def controller_sources
    Dir.glob(Rails.root.join("app/controllers/**/*.rb")).to_h do |path|
      [ path.delete_prefix("#{Rails.root}/"), File.read(path) ]
    end
  end

  def controller_flashes
    controller_sources.flat_map { |path, source| flashes_in(source, path) }
  end

  # By key or by English text over 8 characters, so "Saved." can't match by chance. Boundary-aware:
  # asserting operations.workspaces.create.success must not count for its suffix workspaces.create.success.
  def asserted?(key, values, specs)
    return true if specs.match?(/(?<![\w.])#{Regexp.escape(key)}(?![\w.])/)

    text = values[key]
    text.present? && text.length > 8 && specs.include?(text)
  end

  let(:values) { locale_values }

  # Skips this file, whose comments name keys as examples.
  let(:specs) do
    Dir.glob(Rails.root.join("spec/**/*_spec.rb"))
      .reject { |f| f == __FILE__ }
      .map { |f| File.read(f) }.join("\n")
  end

  # Held in a variable, so no key can be read from the line; a new one fails below until someone checks its spec by hand.
  let(:variable_flashes) do
    {
      "app/controllers/settings/avatars_controller.rb" => [ "message", "result.error_message" ],
      "app/controllers/settings/connected_account_verifications_controller.rb" =>
        [ 'problems.map { |problem| t(CLAIM_PROBLEM_MESSAGES.fetch(problem)) }.join(" ")' ],
      "app/controllers/workspaces/invitations/resends_controller.rb" => [ "t(notice_key)" ],
      "app/controllers/workspaces/invitations_controller.rb" => [ "notice" ],
      "app/controllers/workspaces/logos_controller.rb" => [ "result.error_message" ],
      "app/controllers/workspaces/members_controller.rb" => [ "message" ],
      "app/controllers/workspaces_controller.rb" => [ "message" ]
    }
  end

  # Lines that name a flash without setting one.
  let(:not_flash_setters) { [ 'toast_stream("notice", message)', 'toast_stream("alert", message)' ] }

  it "reads a flash from every controller line that names one" do
    unread = controller_sources.flat_map do |path, source|
      source.lines.each_with_index.filter_map do |line, index|
        next if line.strip.start_with?("#") || line !~ /\b(?:notice|alert)\b/
        next if flash_expression(line) || not_flash_setters.include?(line.strip)

        "#{path}:#{index + 1}: #{line.strip}"
      end
    end

    expect(unread).to be_empty, "the guard cannot read these lines; teach flash_expression the spelling:\n  #{unread.join("\n  ")}"
  end

  it "reads a key from every flash, or the flash is a reviewed variable" do
    unread = controller_flashes.select do |flash|
      path = flash[:at].split(":").first
      flash[:keys].empty? && !variable_flashes.fetch(path, []).include?(flash[:expression])
    end

    expect(unread.map { |flash| "#{flash[:at]}: #{flash[:expression]}" }).to be_empty
  end

  it "catches an unasserted key in each spelling it reads" do
    planted = <<~RUBY
      def create
        redirect_to root_path, notice: t(".planted_lazy")
        flash[:alert] = t("planted.absolute")
        notice += " " + t("planted.suffix")
      end
    RUBY
    keys = flashes_in(planted, "app/controllers/planted_controller.rb").flat_map { |flash| flash[:keys] }

    expect(keys).to eq(%w[planted.create.planted_lazy planted.absolute planted.suffix])
    expect(keys.reject { |key| asserted?(key, values, specs) }).to eq(keys)
  end

  it "asserts every flash a controller sets" do
    unasserted = controller_flashes.flat_map { |flash| flash[:keys] }.uniq.reject { |key| asserted?(key, values, specs) }

    expect(unasserted).to be_empty,
      "these controller flashes are asserted by no spec:\n  #{unasserted.join("\n  ")}\n\n" \
      "Assert the message, not just the redirect — `expect(flash[:notice]).to eq(I18n.t(\"...\"))` " \
      "in the request spec for that action. A redirect-only assertion cannot tell a wrong key " \
      "from a right one."
  end
end
