require "rails_helper"

# A form rendered INSIDE a <turbo-frame> submits into that frame by default.
# If its controller answers with a redirect, Turbo fetches the target page and
# keeps only the matching frame — the flash, and anything else the layout
# renders outside the frame, is fetched and thrown away. The user acts and
# nothing visibly happens.
#
# The members page has now produced this bug twice: the magic-link generate
# form (fixed when it was written, with a comment saying why) and the
# invitation row's Resend/Revoke buttons (#1038, which shipped broken and was
# only caught by a reviewer's throwaway spec). Second instance of a bug class
# means a guard rather than a third fix (#659).
#
# Static ERB analysis, not a rendered page: a rendered-page walk can only see
# the frames some spec happened to visit, and the states it happened to reach
# (a row's Reactivate button only exists for a discarded member). The template
# text is the whole population and it is deterministic. The cost is the
# analyser below — a small ERB block-depth tracker — and the blind spots listed
# in `unwalked`, which the main failure message prints so nobody has to find
# them here first.
RSpec.describe "Code smell: forms inside Turbo frames" do
  # Locals, not constants (see activity_log_immutability_spec for the CI-shard
  # collision that rule exists to prevent).

  # What this guard does NOT see. Printed on failure, because the useful moment
  # to read them is when the census disagrees with you.
  unwalked = [
    "ViewComponent templates: the walk covers app/views only, so a form inside " \
      "a component's own template (the members table sits inside ui :scroll_area) " \
      "is invisible to it.",
    "A quoted turbo_frame: value is taken as a deliberate target without " \
      "checking that it names the ENCLOSING frame. `turbo_frame: \"some_other_frame\"` " \
      "inside members_results reads as intentional here and would still lose a flash.",
    "A computed target — turbo_frame: dom_id(record) — is reported as bare, " \
      "because the analyser reads source text and cannot evaluate it. The fix " \
      "for such a site is an entry in frame_targeting_is_deliberate, not a " \
      "cleverer regex.",
    "render with a non-literal partial name (render partial: some_variable) is " \
      "not followed into the partial."
  ].freeze

  # site => reason, where a site is "<view path> <helper> <path helper>" — the
  # SAME shape as unfixed_offenders below, and deliberately not a bare path.
  # A path key would absolve every future form added to an already-blessed
  # template: a new bare button_to dropped into sessions/new.html.erb's frame
  # would inherit the lookup form's exemption and ship broken. The negative
  # control at the bottom of this file simulates exactly that.
  #
  # A form here submits into its frame ON PURPOSE, because the action answers
  # with something the frame can absorb: a Turbo Stream, or a render of the
  # frame's own content. An entry is a reviewed decision.
  frame_targeting_is_deliberate = {
    "app/views/sessions/new.html.erb form_with session_lookup_path" =>
      "the email lookup posts to sessions/lookups#create, which answers by " \
      "rendering check_email / closed / email_error — each of which carries " \
      "the matching turbo_frame_tag \"sign_in_form\" so Turbo can swap it in " \
      "place. There is no redirect and no flash to lose.",
    "app/views/sessions/lookups/email_error.html.erb form_with session_lookup_path" =>
      "the re-render of that same lookup form, inside the same frame, for the " \
      "invalid-address path. Same destination, same in-frame answer.",
    "app/views/workspaces/members/edit.html.erb form_with workspace_member_path" =>
      "the role form posts to members#update, which branches on the " \
      "Turbo-Frame header: a frame request gets the role_cell partial back " \
      "(the frame's own content), and the last-owner error gets a toast " \
      "Turbo Stream precisely so the message is not left in a dropped flash."
  }.freeze

  # site => reason, one entry per offending form. Entries here are BROKEN, not
  # allowed — a form whose notice is provably swallowed, ledgered because the
  # fix is a behaviour change someone has to own.
  #
  # EMPTY, and meant to stay that way. It held the three _member_row buttons
  # #1050 has now fixed (proven by spec/system/workspaces/member_row_actions_spec.rb).
  # This ledger is asserted exactly, so a new bare form fails the first example
  # rather than landing here: adding an entry is a deliberate act that needs an
  # issue number and a reason, and the ledger can only shrink again afterwards.
  unfixed_offenders = {}.freeze

  view_root = Rails.root.join("app/views")

  # An ERB tag's code without its comments (`<%#` tags and Ruby `#` lines), so prose can say "do" or
  # "button_to" without reading as code.
  erb_tags = lambda do |source|
    source.to_enum(:scan, /<%(?!#)(=|-|)?(.*?)-?%>/m).map do
      match = Regexp.last_match
      { code: match[2].lines.grep_v(/\A\s*#/).join.strip, offset: match.begin(0) }
    end
  end

  opens_block = lambda do |code|
    code.match?(/\bdo\s*(\|[^|]*\|)?\z/) ||
      code.match?(/\A(if|unless|case|begin|while|until)\b/)
  end

  closes_block = ->(code) { code.match?(/\Aend\b/) }

  # The tags that sit inside a turbo_frame_tag block in this template. A
  # partial reached FROM inside a frame is entirely inside one, which is what
  # `all_inside` expresses.
  tags_inside_frames = lambda do |source, all_inside|
    tags = erb_tags.call(source)
    return tags if all_inside

    inside = []
    frame_depths = []
    depth = 0
    tags.each do |tag|
      opening = opens_block.call(tag[:code])
      inside << tag if frame_depths.any?

      if closes_block.call(tag[:code])
        depth -= 1
        frame_depths.pop if frame_depths.last == depth
      elsif opening
        frame_depths << depth if tag[:code].match?(/\bturbo_frame_tag\b/)
        depth += 1
      end
    end
    inside
  end

  # "helper path_helper" — stable across reformatting, unlike a line number.
  signature = lambda do |code|
    helper = code[/\b(button_to|form_with|form_for|form_tag)\b/, 1]
    target = code[/\b(\w+_path)\b/, 1] || code[/\b(\w+_url)\b/, 1] || "?"
    "#{helper} #{target}"
  end

  # One template's worth of classification. Takes SOURCE rather than a path so
  # the negative control can hand it a simulated template.
  classify = lambda do |source, relative, all_inside|
    result = { top: [], named: [], bare: [], renders: [] }

    tags_inside_frames.call(source, all_inside).each do |tag|
      code = tag[:code]

      if code.match?(/\b(button_to|form_with|form_for|form_tag)\b/)
        entry = { site: "#{relative} #{signature.call(code)}", code: code }
        if code.match?(/turbo_frame:\s*(:_top|["']_top["'])/) ||
           code.match?(/data-turbo-frame=["']_top["']/)
          result[:top] << entry
        elsif (name = code[/turbo_frame:\s*["']([^"']+)["']/, 1])
          result[:named] << entry.merge(frame: name)
        else
          result[:bare] << entry
        end
      end

      code.scan(/render\s+(?:layout:\s*|partial:\s*)?["']([\w\/]+)["']/) do |(name)|
        result[:renders] << name
      end
    end

    result
  end

  # A partial name as written in `render`, resolved to a file.
  resolve_partial = lambda do |name, from_relative|
    parts = name.split("/")
    base = parts.pop
    dir = parts.any? ? parts.join("/") : File.dirname(from_relative).sub("app/views/", "")
    Rails.root.join("app/views", dir, "_#{base}.html.erb")
  end

  census = lambda do
    found = { top: [], named: [], bare: [] }
    seen = []

    walk = lambda do |path, all_inside|
      relative = path.relative_path_from(Rails.root).to_s
      next if seen.include?([ relative, all_inside ]) || !path.exist?
      seen << [ relative, all_inside ]

      result = classify.call(path.read, relative, all_inside)
      found[:top].concat(result[:top])
      found[:named].concat(result[:named])
      found[:bare].concat(result[:bare])
      result[:renders].each { |name| walk.call(resolve_partial.call(name, relative), true) }
    end

    Pathname.glob(view_root.join("**/*.erb")).sort.each do |path|
      next unless path.read.include?("turbo_frame_tag")
      walk.call(path, false)
    end

    found
  end

  # The one filter the guard turns on: a bare form is an offender unless its
  # exact SITE is a reviewed exception.
  unabsolved = lambda do |bare|
    bare.reject { |entry| frame_targeting_is_deliberate.key?(entry[:site]) }
  end

  let(:found) { census.call }

  it "every form inside a Turbo frame either escapes to _top, names its frame, or is a reviewed exception" do
    offenders = unabsolved.call(found[:bare]).map { |e| e[:site] }

    expect(offenders).to match_array(unfixed_offenders.keys),
      "A form inside a <turbo-frame> submits into that frame, so a redirect's " \
      "flash never reaches the page (#1038). Give it " \
      "`form: { data: { turbo_frame: \"_top\" } }` (button_to) or " \
      "`data: { turbo_frame: \"_top\" }` (form_with) — or, if the action " \
      "answers with a stream or re-renders the frame, add the SITE to " \
      "frame_targeting_is_deliberate in this spec with its reason.\n" \
      "Unexpected:\n  #{(offenders - unfixed_offenders.keys).join("\n  ")}\n" \
      "Ledgered but no longer found (delete its line):\n  " \
      "#{(unfixed_offenders.keys - offenders).join("\n  ")}\n" \
      "Blind spots this census does not cover:\n  - #{unwalked.join("\n  - ")}"
  end

  # Positive controls. Without these the guard passes just as happily when the
  # walker silently sees nothing — the failure mode that makes a green code
  # smell spec worthless.
  it "sees the two invitation-row buttons that #1038 fixed" do
    expect(found[:top].map { |e| e[:site] }).to include(
      "app/views/workspaces/members/_invitation_row.html.erb button_to workspace_invitation_resend_path",
      "app/views/workspaces/members/_invitation_row.html.erb button_to workspace_invitation_path"
    )
  end

  it "reads a Ruby comment inside a code tag as prose, not a form" do
    source = <<~ERB
      <%= turbo_frame_tag "results" do %>
        <%
          # the confirm button_to renders its own form
          label = "Go"
        %>
      <% end %>
    ERB

    expect(classify.call(source, "app/views/example.html.erb", false)[:bare]).to be_empty
  end

  it "sees the members search form deliberately targeting its own frame" do
    search = found[:named].find { |e| e[:site].start_with?("app/views/workspaces/members/index.html.erb") }

    expect(search).to be_present,
      "The members filter form targets members_results on purpose — a census " \
      "that cannot see it is not reading index.html.erb's frame at all."
    expect(search[:frame]).to eq("members_results")
  end

  # Census for #1051's trigger: the guard trusts a quoted frame target, which holds
  # only while one site names a frame. A second site fails here.
  it "has exactly one form naming its frame, and that name is its own frame" do
    named = found[:named].map { |entry| [ entry[:site], entry[:frame] ] }

    expect(named.size).to eq(1),
      "the census now sees #{named.size} forms naming a frame:\n  " \
      "#{named.map { |site, frame| "#{site} -> #{frame}" }.join("\n  ")}\n\n" \
      "Each one needs the question this guard cannot answer: is that the frame " \
      "the form is enclosed by? If yes, widen this example. If no, it submits " \
      "into a frame that is not on the page and nothing will say so."

    expect(named.first.last).to eq("members_results")
  end

  it "reaches forms in partials rendered inside a frame, not just the frame's own template" do
    reached = (found[:top] + found[:named] + found[:bare]).map { |e| e[:site] }

    expect(reached).to include(a_string_starting_with("app/views/workspaces/members/_invitation_row.html.erb"))
    expect(reached).to include(a_string_starting_with("app/views/workspaces/members/_member_row.html.erb"))
  end

  it "keeps every exception and ledger entry pointed at the exact form it names" do
    all_sites = (found[:top] + found[:named] + found[:bare]).map { |e| e[:site] }

    (frame_targeting_is_deliberate.keys + unfixed_offenders.keys).each do |site|
      expect(all_sites).to include(site),
        "#{site} is listed in this spec but the census finds no such form " \
        "inside a frame. Either the view changed and the entry is dead (a " \
        "renamed path helper renames the site), or the walker stopped " \
        "reaching it. A stale exception is a hole."
    end
  end

  # Negative control for the site-keyed exception map. A path-keyed map passes
  # this spec while silently absolving anything new added to a blessed
  # template; this simulation adds exactly that and proves it is still caught.
  it "does not absolve a NEW bare form added inside an already-excepted template's frame" do
    relative = "app/views/sessions/lookups/email_error.html.erb"
    source = Rails.root.join(relative).read
    expect(source).to include("turbo_frame_tag"), "the simulation's fixture template moved"

    # Drop a bare button_to immediately inside the frame block.
    simulated = source.sub(
      /(<%=\s*turbo_frame_tag[^%]*%>)/,
      "\\1\n  <%= button_to \"Probe\", probe_path, method: :post %>"
    )
    expect(simulated).not_to eq(source), "the injection point moved; the simulation proves nothing"

    result = classify.call(simulated, relative, false)
    sites = unabsolved.call(result[:bare]).map { |e| e[:site] }

    expect(sites).to include("#{relative} button_to probe_path"),
      "A new bare form inside an already-excepted template's frame was " \
      "absolved. frame_targeting_is_deliberate must stay keyed by SITE " \
      "(\"path helper\"), never by path alone."
    # And the real, reviewed form in that same template is still recognised as
    # the exception it is — the fix must not work by simply forgetting it.
    expect(result[:bare].map { |e| e[:site] })
      .to include("#{relative} form_with session_lookup_path")
    expect(sites).not_to include("#{relative} form_with session_lookup_path")
  end
end
