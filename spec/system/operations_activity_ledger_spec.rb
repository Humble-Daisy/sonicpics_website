# frozen_string_literal: true

require "rails_helper"

# The operations activity ledger in a real browser: the filter band applying
# into the results frame on change, the custom-range popover, the pivot out of
# a row's details, the rows-per-page control — each audited at WCAG 2.2 AAA in
# both themes.
#
# Every I18n.t call below passes no vocabulary noun keyword (workspace:,
# project:) — the backend injects %{workspace}/%{project}/etc itself, and a
# caller's literal would win over it and stop discriminating in a fork that
# renamed the noun. See /docs/developer/i18n (Vocabulary).
#
# :with_zero_workspaces keeps the operator out of the feed's own rows, so
# every assertion below is about the fixtures this file created.
RSpec.describe "Operations activity ledger", type: :system do
  let(:operator) { create(:user, :with_zero_workspaces).tap { |u| Operatorship.grant!(user: u) } }
  let!(:acme) { create(:workspace, name: "Acme Robotics") }
  let!(:beta) { create(:workspace, name: "Beta Works") }
  let!(:priya) { create(:user, first_name: "Priya", last_name: "Nair") }
  # A deterministic `membership.created` row — the positive control the kind
  # filter is measured against.
  let!(:priya_membership) { create(:membership, user: priya, workspace: acme) }

  before do
    acting_as(priya) { plan_named(acme, "Launch plan") }
    plan_named(beta, "Beta plan")
    sign_in_via_form(operator)
  end

  def within_results(&) = within("turbo-frame#activity_results", &)

  # A `project.created` row names nothing the page can show: Trackable writes
  # no metadata for a creation and the sentence is "created the <project>".
  # A RENAME does — its `changes` metadata carries the name, which the details
  # <dl> renders — so a plan is created and then renamed. Same handle the
  # request specs use (spec/requests/operations/activity_logs_filters_spec.rb).
  def plan_named(workspace, name)
    create(:project, workspace: workspace).update!(name: name)
  end

  # Acting AS someone is a session, not an assignment: Current.user delegates
  # to Current.session (spec/models/activity_log_filters_spec.rb's pattern).
  # The rename row, addressed the way the page addresses it — workspace column
  # plus the sentence. The project's NAME cannot be the locator: it lives
  # inside the closed <details>, which is exactly what opening the row proves.
  def rename_row
    find("tbody tr", text: /Acme Robotics.*#{Regexp.escape(I18n.t("activity.actions.project.updated"))}/m)
  end

  # The band's one range control states the APPLIED window: a preset reads its
  # sentence-case control label ("Last 30 days" — ranges_menu.*, NOT the
  # lowercase ranges_long.* the summary sentence uses), a custom range the
  # bounds themselves
  # (ActivityLedgerHelper#ledger_range_label). So the trigger's accessible name
  # changes with the filter, and every click_button below names the window that
  # is currently on.
  def custom_range_trigger_label(from, to)
    I18n.t("operations.activity_logs.index.ranges.custom_trigger",
           from: I18n.l(from, format: :ledger_short), to: I18n.l(to, format: :ledger_day))
  end

  # Addressed by its own id. The combobox's text input used to carry neither id
  # nor name — both landed on the wrapper and the hidden field — so this had to
  # reach it by accessible name, which only works with Capybara.enable_aria_label
  # (which this suite does not set). The component now derives `<wrapper>-input`.
  def workspace_combobox
    find_field("workspace-input")
  end

  it "renders the default window AAA-clean in both themes, with an open details row" do
    visit operations_activity_logs_path
    within_results { expect(page).to have_css("tbody tr", minimum: 2) }

    rename_row.find("summary").click

    # The rename's `changes` metadata — the one per-record handle the ledger
    # puts on the page, and proof the opened row is the one addressed above.
    expect(page).to have_css("details[open] dd", text: "Launch plan")
    expect(page).to have_css("details[open] dd",
      text: I18n.t("operations.activity_logs.index.details.only_person", email: priya.email_address))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # The caveats popover is the one control on the card whose trigger carries no
  # visible text, so its open state is where an unnamed icon button or an
  # unreadable panel would show up. Audited open, both themes.
  it "opens the results caveats from the toolbar, AAA in both themes" do
    visit operations_activity_logs_path
    within_results { expect(page).to have_css("tbody tr", minimum: 1) }

    click_button I18n.t("operations.activity_logs.index.about.label")
    expect(page).to have_text(I18n.t("operations.activity_logs.index.about.best_effort"))
    expect(page).to have_text(I18n.t("operations.activity_logs.index.about.derived"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  it "applies a select change inside the frame, advances the URL, keeps focus, and announces the count" do
    visit operations_activity_logs_path
    # Positive control: the sentence the kind filter must remove is on the
    # unfiltered page first, so its later absence measures the filter.
    within_results { expect(page).to have_text(I18n.t("activity.actions.membership.created")) }

    # Cuprite's `select` only DISPATCHES synthetic focus/blur events at the
    # <select> — it never moves document.activeElement, which stays on <body>.
    # A real pointer or Tab lands focus on the control before the change, so
    # this puts it there; otherwise the assertion below would measure the
    # driver (and navigation_focus.js's correct "focus is parked" fallback)
    # instead of the frame swap.
    cdp_execute("document.getElementById('kind').focus()")
    select I18n.t("activity.kinds.project"), from: "kind"

    within_results { expect(page).to have_css("h2", text: I18n.t("activity.kinds.project")) }
    expect(page).to have_current_path(/kind=project/)
    # The filter form sits OUTSIDE the frame precisely so the swap never takes
    # focus off the control that caused it.
    expect(page.evaluate_script("document.activeElement.id")).to eq("kind")
    expect(page).to have_css("#activity_results_status", text: I18n.t("activity.kinds.project"), visible: :all)
    within_results { expect(page).to have_no_text(I18n.t("activity.actions.membership.created")) }
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  it "narrows by workspace through the combobox without an Apply button" do
    visit operations_activity_logs_path
    # Every control applies on change; the only visible submit button on the
    # page is the range panel's "Use this range", which carries name="range".
    expect(page).to have_no_css("form button[type=submit]:not([name=range])")
    within_results do
      expect(page).to have_link("Acme Robotics")
      expect(page).to have_link("Beta Works")
    end

    workspace_combobox.click
    cdp_browser.keyboard.type("Acme")
    find("[role=option]", text: "Acme Robotics").click

    within_results do
      expect(page).to have_link("Acme Robotics")
      expect(page).to have_no_text("Beta Works")
    end
    expect(page).to have_current_path(/workspace=#{Regexp.escape(acme.slug)}/)
  end

  it "switches the range from the one trigger and accepts a custom range from its panel" do
    visit operations_activity_logs_path
    # The trigger names the applied window, so on a fresh visit it is "Last 30
    # days" — the default — and the presets live behind it.
    click_button I18n.t("operations.activity_logs.index.ranges_menu.30d")
    click_button I18n.t("operations.activity_logs.index.ranges_menu.all")
    expect(page).to have_current_path(/range=all/)
    within_results { expect(page).to have_css("h2", text: I18n.t("operations.activity_logs.index.ranges_long.all")) }

    click_button I18n.t("operations.activity_logs.index.ranges_menu.all")
    fill_in "from", with: "2026-09-03"
    fill_in "to", with: Date.current.iso8601
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    click_button I18n.t("operations.activity_logs.index.ranges.use")
    expect(page).to have_current_path(/range=custom/)
    expect(page).to have_current_path(/from=2026-09-03/)
  end

  # Enter in a text field clicks the form's DEFAULT button — the first submit
  # button in tree order owning the form. The range group's submitters are
  # form-associated, so before the band grew a nameless default button that was
  # "24h", and pressing Enter after typing an email silently narrowed the window.
  it "keeps the applied range when Enter submits from the search box" do
    visit operations_activity_logs_path(range: "all")
    within_results { expect(page).to have_css("h2", text: I18n.t("operations.activity_logs.index.ranges_long.all")) }

    fill_in "q", with: priya.email_address
    find("#q").send_keys(:enter)

    # The summary naming the person is what proves the submit landed, so the
    # path assertions below are about a page that actually re-filtered.
    within_results { expect(page).to have_css("h2", text: priya.email_address) }
    expect(page).to have_current_path(/q=#{Regexp.escape(CGI.escape(priya.email_address))}/)
    expect(page).to have_current_path(/range=all/)
    expect(page).to have_no_current_path(/range=24h/)
  end

  # Typing is the search: the results re-filter after the debounce without
  # Enter or leaving the box (the form's change->submit alone fired only on
  # blur or Enter), focus stays in the box, and Escape clears it.
  it "searches as you type and clears on Escape" do
    visit operations_activity_logs_path
    within_results { expect(page).to have_link("Beta Works") }

    fill_in "q", with: priya.email_address
    within_results do
      expect(page).to have_no_text("Beta Works")
      expect(page).to have_css("h2", text: priya.email_address)
    end
    expect(page).to have_current_path(/q=#{Regexp.escape(CGI.escape(priya.email_address))}/)
    expect(page.evaluate_script("document.activeElement.id")).to eq("q")

    find("#q").send_keys(:escape)
    within_results { expect(page).to have_link("Beta Works") }
    expect(find("#q").value).to eq("")
  end

  # The box resolves a name, not just an address. Two people share a first name
  # here on purpose: the summary has to name both, or an operator cannot tell
  # which Priya the rows in front of them belong to.
  it "resolves a typed first name to everyone who carries it, AAA in both themes" do
    patel = create(:user, first_name: "Priya", last_name: "Patel")
    acting_as(patel) { plan_named(beta, "Patel plan") }
    visit operations_activity_logs_path

    fill_in "q", with: "priya"
    find("#q").send_keys(:enter)

    within_results do
      expect(page).to have_css("h2", text: I18n.t("operations.activity_logs.index.summary.matching",
        query: "priya", names: "Priya Nair, Priya Patel"))
      expect(page).to have_link("Acme Robotics")
      expect(page).to have_link("Beta Works")
    end
    expect(page).to have_current_path(/q=priya/)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # The custom-range state is the one where the band and the popover both hold a
  # control named `from`/`to`. While the band carried its own hidden from/to,
  # `hidden_field_tag` gave them id="from"/id="to", so the popover's <label for>
  # resolved to the HIDDEN field and the visible date input had no accessible
  # name at all — an axe `label` violation only this state can produce.
  it "keeps the popover AAA-clean in both themes while a custom range is applied" do
    visit operations_activity_logs_path(range: "custom", from: "2026-09-03", to: Date.current.iso8601)
    within_results { expect(page).to have_css("tbody tr", minimum: 1) }

    click_button custom_range_trigger_label(Date.new(2026, 9, 3), Date.current)
    expect(page).to have_field("from", with: "2026-09-03")
    expect(page).to have_field("to", with: Date.current.iso8601)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # Every range control is a submitter of the band form it sits OUTSIDE of
  # (form="activity_filters"), and each carries data-turbo-frame="_top" so the
  # band re-renders with the new range rather than going stale behind a frame
  # swap. Turbo reads data-turbo-frame off the submitter before the form.
  it "keeps the rest of the filter state when the range changes, and vice versa" do
    visit operations_activity_logs_path
    cdp_execute("document.getElementById('kind').focus()")
    select I18n.t("activity.kinds.project"), from: "kind"
    within_results { expect(page).to have_css("h2", text: I18n.t("activity.kinds.project")) }

    # A range click must carry the Kind that was applied through the frame.
    click_button I18n.t("operations.activity_logs.index.ranges_menu.30d")
    click_button I18n.t("operations.activity_logs.index.ranges_menu.all")
    expect(page).to have_current_path(/kind=project/)
    expect(page).to have_current_path(/range=all/)
    within_results { expect(page).to have_css("h2", text: I18n.t("operations.activity_logs.index.ranges_long.all")) }

    # And the band itself re-rendered: the trigger reads the new window, and the
    # panel marks it current.
    range_trigger = find("button[aria-controls=activity_range]")
    expect(range_trigger).to have_text(I18n.t("operations.activity_logs.index.ranges_menu.all"))
    range_trigger.click
    expect(page).to have_css("[role=dialog] nav button[aria-current='true']",
      text: I18n.t("operations.activity_logs.index.ranges_menu.all"))
    # Closed by its own trigger's state, not by "no dialog on the page" — the
    # cookie banner is a role=dialog too.
    range_trigger.send_keys(:escape)
    expect(page).to have_css("button[aria-controls=activity_range][aria-expanded=false]")

    # …and a Kind change afterwards must not silently revert the range to 30d.
    cdp_execute("document.getElementById('kind').focus()")
    select I18n.t("activity.kinds.membership"), from: "kind"
    within_results { expect(page).to have_css("h2", text: I18n.t("activity.kinds.membership")) }
    expect(page).to have_current_path(/range=all/)
  end

  it "pivots into one person from a row's details and shows the empty state when nothing matches" do
    visit operations_activity_logs_path
    within_results { expect(page).to have_link("Beta Works") }

    rename_row.find("summary").click
    within("details[open]") do
      click_link I18n.t("operations.activity_logs.index.details.only_person", email: priya.email_address)
    end

    within_results do
      expect(page).to have_link("Acme Robotics")
      expect(page).to have_no_text("Beta Works")
    end
    expect(page).to have_current_path(/q=#{Regexp.escape(CGI.escape(priya.email_address))}/)

    visit operations_activity_logs_path(q: "nobody@example.com")
    within_results { expect(page).to have_text(I18n.t("operations.activity_logs.index.empty")) }
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  it "changes rows per page from the footer" do
    visit operations_activity_logs_path
    within_results { click_link "25" }
    expect(page).to have_current_path(/rows=25/)
    within_results { expect(page).to have_css("nav a[aria-current='true']", text: "25") }
  end

  # Every control that must navigate the whole page hands focus back to
  # itself — or to the choice it just made — in the new document (2.4.3), via
  # data-focus-key (navigation_focus.js). Read from document.activeElement:
  # the one fact a keyboard user experiences.
  # Each step waits for the NEW page's rendered state before reading focus:
  # an advance visit changes the URL when it starts, not when it renders, so
  # have_current_path alone can be satisfied while the old page is still up.
  it "returns focus to the control that navigated the page" do
    visit operations_activity_logs_path
    within_results { click_link I18n.t("operations.activity_logs.index.columns.when") }
    within_results { expect(page).to have_css("th[aria-sort='ascending']") }
    expect(active_element("closest('th').getAttribute('aria-sort')")).to eq("ascending")

    within_results { click_link "100" }
    within_results { expect(page).to have_css("nav a[aria-current='true']", text: "100") }
    expect(active_element("getAttribute('aria-current')")).to eq("true")
    expect(active_element("textContent.trim()")).to eq("100")

    find("button[aria-controls=activity_range]").click
    click_button I18n.t("operations.activity_logs.index.ranges_menu.7d")
    expect(page).to have_css("button[aria-controls=activity_range]", text: I18n.t("operations.activity_logs.index.ranges_menu.7d"))
    expect(active_element("getAttribute('aria-controls')")).to eq("activity_range")

    rename_row.find("summary").click
    within("details[open]") do
      click_link I18n.t("operations.activity_logs.index.details.only_person", email: priya.email_address)
    end
    within_results { expect(page).to have_css("h2", text: priya.email_address) }
    expect(active_element("id")).to eq("q")
  end

  def active_element(expression)
    page.evaluate_script("document.activeElement && document.activeElement.#{expression}")
  end

  # At phone width the range trigger spans the band, so its panel is anchored to
  # a box that already reaches both gutters and only position-area's flip
  # fallbacks keep the panel on-screen. Measured, not trusted: a panel hanging
  # off the right edge is invisible until the page scrolls sideways.
  # Last in the file — it resizes the shared window.
  it "keeps the range panel inside a 390px viewport" do
    page.current_window.resize_to(390, 1000)
    visit operations_activity_logs_path
    within_results { expect(page).to have_css("tbody tr", minimum: 1) }
    expect(page.evaluate_script("document.documentElement.scrollWidth")).to be <= 390

    click_button I18n.t("operations.activity_logs.index.ranges_menu.30d")
    expect(page).to have_css("[role=dialog]")

    box = page.evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector('[role=dialog]').getBoundingClientRect();
        return { left: r.left, right: r.right };
      })()
    JS

    expect(box["left"]).to be >= 0
    expect(box["right"]).to be <= 390

    # The other states a phone reaches that the gate never scored: the caveats
    # popover open, a row's details open inside the sideways-scrolling region
    # (with the toolbar and footer pinned outside it), and an empty result with
    # its Clear link.
    find("button[aria-controls=activity_range]").send_keys(:escape)
    find("button[aria-controls=activity_about]").click
    expect(page).to have_css("#activity_about:not([hidden])")
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
    find("button[aria-controls=activity_about]").send_keys(:escape)

    rename_row.find("summary").click
    expect(page).to have_css("details[open]")
    within_results do
      expect(page).to have_css("div[role=region] table")
      expect(page).to have_no_css("div[role=region] [data-slot=toolbar]")
      expect(page).to have_no_css("div[role=region] [data-slot=footer]")
    end
    # Opening the row scrolls the caveats button under the sticky header, where a long app name overlaps it.
    page.scroll_to(0, 0)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    visit operations_activity_logs_path(q: "nobody@example.com")
    within_results do
      expect(page).to have_text(I18n.t("operations.activity_logs.index.empty"))
      expect(page).to have_link(I18n.t("operations.activity_logs.index.summary.clear"))
    end
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end
  # The search shape of the Workspace filter is what a GROWN instance sees, and
  # nothing else in this suite ever renders it — so without this example the AAA
  # gate would score only the shape small instances get, and a fork would be the
  # first to find out. Every state the shape can reach is audited here: the bare
  # search box, several candidates offered, no match, and a filter applied.
  it "audits the large-instance workspace search in every state it can reach" do
    stub_const("Operations::ActivityLogsController::WORKSPACE_PICKER_LIMIT", 1)

    visit operations_activity_logs_path
    expect(page).to have_field("workspace_q")
    expect(page).to have_no_css("[data-filter=workspace] [role=option]")
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Several matches: the choices are offered rather than one being guessed.
    visit operations_activity_logs_path(workspace_q: "o")
    expect(page).to have_css("[data-role=workspace-candidate]", minimum: 2)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # No match — a message, not a silently unfiltered page.
    visit operations_activity_logs_path(workspace_q: "zzz-no-such-workspace")
    expect(page).to have_text(
      I18n.t("operations.activity_logs.index.filters.workspace_no_match", query: "zzz-no-such-workspace")
    )
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Applied, with the clear affordance — the state that replaces a selected
    # option, since there is no option list here to hold one.
    visit operations_activity_logs_path(workspace: acme.slug)
    expect(page).to have_text(I18n.t("operations.activity_logs.index.filters.workspace_applied", name: acme.name))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # And it clears back to the search box.
    find("[data-filter=workspace] a").click
    expect(page).to have_field("workspace_q")
  end

  # The "most active" strip is new UI, so it needs its own row in the gate: the
  # existing examples render a ledger whose rows all share one actor, where the
  # strip is a single chip and its wrapping, target size and contrast are never
  # exercised.
  it "audits the most-active strip, and its entries narrow to one person" do
    other = create(:user, first_name: "Grace", last_name: "Hopper")
    acting_as(other) { plan_named(acme, "Grace plan") }

    visit operations_activity_logs_path(range: "all")
    expect(page).to have_css("[data-role=top-actor]", minimum: 2)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # A way INTO the ledger: clicking a name applies the person filter through the
    # same `q` pivot the row details use, and the box outside the frame shows it.
    within("[data-role=top-actors]") { click_link(match: :first) }
    expect(page).to have_field("q", with: priya.email_address).or have_field("q", with: other.email_address)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end
end
