require "rails_helper"

RSpec.describe "Operations activity ledger filters", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in(operator) }

  def rows(body) = Capybara.string(body).all("tbody tr")

  # A `project.created` row names nothing the page can show: Trackable writes
  # no metadata for a creation and the sentence is "created the <project>".
  # A RENAME does — its `changes` metadata carries the name, which the details
  # row renders — so these examples label a row by renaming its project, the
  # one per-record handle the ledger actually puts on the page. Returns the
  # rename's own activity row.
  def plan_named(workspace, name)
    project = create(:project, workspace: workspace)
    project.update!(name: name)
    project.activities.order(:created_at, :id).last
  end

  # ActivityLog#readonly? blocks instance-level update_column too (it is
  # persisted?-gated, not save-path-specific) — go relation-level, the same
  # door spec/models/activity_log_filters_spec.rb uses.
  def backdate(activity_log, to)
    ActivityLog.where(id: activity_log.id).update_all(created_at: to)
  end

  # Acting AS someone is a session, not an assignment: Current.user delegates
  # to Current.session (spec/models/activity_log_filters_spec.rb's pattern).
  it "applies the 30-day window by default and widens on range=all" do
    workspace = create(:workspace, name: "Alpha")
    backdate(plan_named(workspace, "Old plan"), 40.days.ago)

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Old plan")

    get operations_activity_logs_path(range: "all")
    expect(response.body).to include("Old plan")
  end

  it "filters by workspace slug and by the instance level" do
    alpha = create(:workspace, name: "Alpha")
    beta  = create(:workspace, name: "Beta")
    plan_named(alpha, "Alpha plan")
    plan_named(beta, "Beta plan")
    Operatorship.grant!(user: create(:user, first_name: "Gale", last_name: "Grantee"))

    get operations_activity_logs_path(workspace: alpha.slug)
    expect(response.body).to include("Alpha plan")
    expect(response.body).not_to include("Beta plan")

    get operations_activity_logs_path(workspace: "instance")
    expect(response.body).to include("granted Gale Grantee operator access")
    expect(response.body).not_to include("Alpha plan")
  end

  it "filters by kind on the stored action prefix and ignores unknown kinds" do
    workspace = create(:workspace, name: "Alpha")
    plan_named(workspace, "Alpha plan")
    joined = I18n.t("activity.actions.membership.created")

    # Positive control: the sentence the kind filter must remove is on the
    # unfiltered page, so its absence below can only mean the filter ran.
    get operations_activity_logs_path
    expect(Capybara.string(response.body)).to have_text(joined)

    get operations_activity_logs_path(kind: "project")
    expect(response.body).to include("Alpha plan")
    expect(Capybara.string(response.body)).to have_no_text(joined)

    get operations_activity_logs_path(kind: "bogus")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Alpha plan")
    expect(Capybara.string(response.body)).to have_text(joined)
  end

  it "resolves an exact email address, whatever its case" do
    person = create(:user, first_name: "Priya", last_name: "Nair")
    workspace = create(:workspace, name: "Alpha")
    acting_as(person) { plan_named(workspace, "Priya plan") }
    plan_named(workspace, "Other plan")

    get operations_activity_logs_path(q: person.email_address.upcase)
    expect(response.body).to include("Priya plan")
    expect(response.body).not_to include("Other plan")
    expect(Capybara.string(response.body)).to have_text(
      I18n.t("operations.activity_logs.index.summary.matching",
             query: person.email_address, names: "Priya Nair")
    )
  end

  it "resolves a name to every user who carries it" do
    nair  = create(:user, first_name: "Priya", last_name: "Nair")
    patel = create(:user, first_name: "Priya", last_name: "Patel")
    workspace = create(:workspace, name: "Alpha")
    acting_as(nair)  { plan_named(workspace, "Nair plan") }
    acting_as(patel) { plan_named(workspace, "Patel plan") }
    plan_named(workspace, "Other plan")

    get operations_activity_logs_path(q: "priya")
    expect(response.body).to include("Nair plan")
    expect(response.body).to include("Patel plan")
    expect(response.body).not_to include("Other plan")
    expect(Capybara.string(response.body)).to have_text(
      I18n.t("operations.activity_logs.index.summary.matching",
             query: "priya", names: "Priya Nair, Priya Patel")
    )
  end

  it "resolves a workspace name fragment and a project name" do
    alpha = create(:workspace, name: "Acme Robotics")
    beta  = create(:workspace, name: "Beta Works")
    plan_named(alpha, "Alpha plan")
    plan_named(beta, "Beta plan")

    get operations_activity_logs_path(q: "robot")
    expect(response.body).to include("Alpha plan")
    expect(response.body).not_to include("Beta plan")
    expect(Capybara.string(response.body)).to have_text(
      I18n.t("operations.activity_logs.index.summary.matching", query: "robot", names: "Acme Robotics")
    )

    # A project name reaches the project's OWN rows, wherever they sit.
    get operations_activity_logs_path(q: "beta plan")
    expect(response.body).to include("Beta plan")
    expect(response.body).not_to include("Alpha plan")
  end

  it "says so when a query matches nothing, rather than looking like an empty instance" do
    plan_named(create(:workspace, name: "Alpha"), "Alpha plan")

    get operations_activity_logs_path(q: "zzz")
    expect(rows(response.body)).to be_empty
    html = Capybara.string(response.body)
    expect(html).to have_text(I18n.t("operations.activity_logs.index.summary.no_match", query: "zzz"))
    expect(html).to have_text(I18n.t("operations.activity_logs.index.empty"))
  end

  it "keeps `person` working as an alias and carries the filter forward as `q`" do
    person = create(:user, first_name: "Priya", last_name: "Nair")
    workspace = create(:workspace, name: "Alpha")
    acting_as(person) { plan_named(workspace, "Priya plan") }
    plan_named(workspace, "Other plan")

    get operations_activity_logs_path(person: person.email_address)
    expect(response.body).to include("Priya plan")
    expect(response.body).not_to include("Other plan")

    rows_links = Capybara.string(response.body)
      .all("nav[aria-label='#{I18n.t('operations.activity_logs.index.rows.label')}'] a")
      .map { |link| link[:href] }
    expect(rows_links).to all(include("q=#{CGI.escape(person.email_address)}"))
    expect(rows_links.join(" ")).not_to include("person=")
  end

  it "pivots out of a row's details on `q`" do
    person = create(:user, first_name: "Priya", last_name: "Nair")
    workspace = create(:workspace, name: "Alpha")
    create(:membership, user: person, workspace: workspace)

    get operations_activity_logs_path
    pivot = Capybara.string(response.body)
      .first("tbody a", text: I18n.t("operations.activity_logs.index.details.only_person",
                                     email: person.email_address), visible: :all)
    expect(pivot[:href]).to include("q=#{CGI.escape(person.email_address)}")
  end

  # A row's details link out both ways: to the person's own operations page,
  # and back into the ledger narrowed to them or to the workspace. The pivot
  # links say what they narrow (2.4.9) — two "only ‹email›" links can share a
  # row — with the visible words kept inside the name (2.5.3).
  it "links a row's details to the person's page and names what each pivot narrows" do
    person = create(:user, first_name: "Priya", last_name: "Nair")
    workspace = create(:workspace, name: "Alpha")
    create(:membership, user: person, workspace: workspace)

    get operations_activity_logs_path
    details = Capybara.string(response.body).first("tbody details", visible: :all)
    expect(details).to have_link("Priya Nair", href: operations_user_path(person), visible: :all)
    pivot = details.find("a", text: I18n.t("operations.activity_logs.index.details.only_person", email: person.email_address), visible: :all)
    expect(pivot[:"aria-label"]).to include(person.email_address).and contain_visible_text(pivot.text)
    scope = details.find("a", text: I18n.t("operations.activity_logs.index.details.only_workspace"), visible: :all)
    expect(scope[:href]).to include("workspace=#{workspace.slug}")
    expect(scope[:"aria-label"]).to include("Alpha").and contain_visible_text(scope.text)
  end

  # Over the cap the decrypt pass is not run at all; the box still answers an
  # exact address, and the summary says which half of it is off.
  it "stops searching names on an instance over the name limit and says so" do
    stub_const("User::Search::NAME_SEARCH_LIMIT", 0)
    person = create(:user, first_name: "Priya", last_name: "Nair")
    workspace = create(:workspace, name: "Alpha")
    acting_as(person) { plan_named(workspace, "Priya plan") }

    get operations_activity_logs_path(q: "nair")
    expect(rows(response.body)).to be_empty
    html = Capybara.string(response.body)
    expect(html).to have_text(I18n.t("operations.activity_logs.index.summary.names_skipped"))

    get operations_activity_logs_path(q: person.email_address)
    expect(response.body).to include("Priya plan")
  end

  it "sorts oldest first on direction=asc" do
    workspace = create(:workspace, name: "Alpha")
    first = plan_named(workspace, "First plan")
    plan_named(workspace, "Second plan")
    backdate(first, 2.days.ago)

    get operations_activity_logs_path(sort: "created_at", direction: "asc")
    body = response.body
    expect(body.index("First plan")).to be < body.index("Second plan")
  end

  # The Workspace header is the ledger's second sort. The header that is not
  # active reads aria-sort="none", the active one names its direction, and the
  # band seeds `sort` so a filter change keeps it.
  it "sorts by workspace name on sort=workspace and marks the active header" do
    plan_named(create(:workspace, name: "Zeta"), "Zeta plan")
    plan_named(create(:workspace, name: "Alpha"), "Alpha plan")

    get operations_activity_logs_path(sort: "workspace", direction: "asc")
    body = response.body
    expect(body.index("Alpha plan")).to be < body.index("Zeta plan")
    html = Capybara.string(body)
    expect(html).to have_css("thead th[aria-sort='ascending']", text: I18n.t("operations.activity_logs.index.columns.workspace"))
    expect(html).to have_css("thead th[aria-sort='none']", text: I18n.t("operations.activity_logs.index.columns.when"))
    hidden = html.all("form#activity_filters > input[type=hidden]", visible: :all).to_h { |f| [ f[:name], f[:value] ] }
    expect(hidden).to include("sort" => "workspace", "direction" => "asc")

    get operations_activity_logs_path(sort: "workspace", direction: "desc")
    body = response.body
    expect(body.index("Zeta plan")).to be < body.index("Alpha plan")

    # An unknown sort falls back to time, and the bare page seeds no sort.
    get operations_activity_logs_path(sort: "actor")
    html = Capybara.string(response.body)
    expect(html).to have_css("thead th[aria-sort='descending']", text: I18n.t("operations.activity_logs.index.columns.when"))
    expect(html.all("form#activity_filters > input[type=hidden]", visible: :all).map { |f| f[:name] }).not_to include("sort")
  end

  it "caps rows=all at 500 and says so" do
    stub_const("Operations::ActivityLogsController::ALL_ROWS", 3)
    5.times { create(:workspace) }

    get operations_activity_logs_path(rows: "all")
    expect(rows(response.body).size).to eq(3)
    expect(Capybara.string(response.body)).to have_text(
      I18n.t("operations.activity_logs.index.rows.capped", limit: 3, count: ActivityLog.for_operations_feed.count)
    )
  end

  it "honours a limit off the query string, capped at the all-rows ceiling" do
    stub_const("Operations::ActivityLogsController::ALL_ROWS", 3)
    5.times { create(:workspace) }

    get operations_activity_logs_path(limit: "2")
    expect(rows(response.body).size).to eq(2)

    get operations_activity_logs_path(limit: "100")
    expect(rows(response.body).size).to eq(3)
  end

  # The filter band lives OUTSIDE the results frame, so a frame-local swap
  # cannot re-render it. Every link inside the frame therefore navigates the
  # whole page; only control CHANGES stay frame-local (for focus).
  it "points every link inside the results frame at _top" do
    workspace = create(:workspace, name: "Alpha")
    plan_named(workspace, "Alpha plan")

    get operations_activity_logs_path(kind: "project")
    frame = Capybara.string(response.body).find("turbo-frame#activity_results", visible: :all)
    links = frame.all("a", visible: :all)

    expect(links.size).to be >= 3 # Clear, the sort header, four Rows links
    expect(links.map { |link| link[:"data-turbo-frame"] }.uniq).to eq([ "_top" ])
  end

  # The uniformity example above sees only one page, so pagy's own anchors are
  # not in it. They are links inside the frame like any other and need _top too;
  # pagy builds them itself, through its anchor_string seam.
  it "points pagy's page links at _top as well" do
    55.times { |i| create(:workspace, name: "WS #{i}") }

    get operations_activity_logs_path
    nav_links = Capybara.string(response.body).all("nav.series-nav a[href]", visible: :all)

    expect(nav_links.size).to be >= 2
    expect(nav_links.map { |link| link[:"data-turbo-frame"] }.uniq).to eq([ "_top" ])
  end

  # The band holds ONE range control now: its panel carries the four presets and
  # the custom window. All five stay submitters of the band form from OUTSIDE it
  # (form=) — a plain link's href is frozen at page load, and the band is not
  # re-rendered by a frame-local Kind change, so links silently dropped it.
  # Each targets _top so the band re-renders with the new range.
  it "keeps every range control in the panel a _top submitter of the band form" do
    create(:workspace, name: "Alpha")

    get operations_activity_logs_path(range: "custom", from: "2026-09-03", to: "2026-09-17")
    html = Capybara.string(response.body)
    submitters = html.all("[role=dialog] button[name=range]", visible: :all)

    expect(submitters.size).to eq(ActivityLog::Range::KEYS.size) # four presets + "Use this range"
    expect(submitters.map { |b| b[:value] })
      .to eq(ActivityLog::Range::KEYS.without("custom") + [ "custom" ])
    expect(submitters.map { |b| b[:form] }.uniq).to eq([ "activity_filters" ])
    expect(submitters.map { |b| b[:"data-turbo-frame"] }.uniq).to eq([ "_top" ])
    # Nothing outside the panel submits a range — the band is one trigger.
    expect(html.all("button[name=range]", visible: :all).size).to eq(submitters.size)
    # The date inputs are the from/to carriers and reach the form the same way.
    expect(html.all("input[type=date]", visible: :all).map { |i| i[:form] }.uniq).to eq([ "activity_filters" ])

    # The trigger's label IS the applied window, so the band states its own state
    # with no second control to read.
    expect(html.find("button[aria-controls=activity_range]", visible: :all).text).to include(
      I18n.t("operations.activity_logs.index.ranges.custom_trigger",
             from: I18n.l(Date.new(2026, 9, 3), format: :ledger_short),
             to: I18n.l(Date.new(2026, 9, 17), format: :ledger_day))
    )

    # A preset window: exactly one panel control is current, and the trigger reads it.
    get operations_activity_logs_path(range: "all")
    html = Capybara.string(response.body)
    current = html.all("[role=dialog] nav button[aria-current='true']", visible: :all)

    expect(current.map(&:text)).to eq([ I18n.t("operations.activity_logs.index.ranges_menu.all") ])
    expect(html.find("button[aria-controls=activity_range]", visible: :all).text)
      .to include(I18n.t("operations.activity_logs.index.ranges_menu.all"))
  end

  # A link in a table cell is left-aligned and 44px tall (.btn-cell-link), not
  # the centred .btn-text — that one is fenced to action rows (#772), where its
  # rest-state affordance is sitting beside a primary button.
  it "styles the cell links with .btn-cell-link on the ledger and the workspaces list" do
    workspace = create(:workspace, name: "Alpha")
    plan_named(workspace, "Alpha plan")

    get operations_activity_logs_path
    expect(Capybara.string(response.body))
      .to have_css("tbody td a.btn-cell-link[href='#{operations_workspace_path(workspace)}']")

    get operations_workspaces_path
    expect(Capybara.string(response.body))
      .to have_css("tbody th[scope=row] a.btn-cell-link[href='#{operations_workspace_path(workspace)}']")
  end

  # `hidden_field_tag` derives an id from the name, so a hidden `from` shadowed
  # the visible date input of the same name and stole its <label for>.
  it "gives the band's hidden fields no id, so no visible control is shadowed" do
    create(:workspace, name: "Alpha")

    get operations_activity_logs_path(range: "custom", from: "2026-09-03", to: "2026-09-17", rows: "100")
    html = Capybara.string(response.body)

    expect(html.all("form#activity_filters > input[type=hidden]", visible: :all).map { |f| f[:name] })
      .to contain_exactly("range", "rows")
    expect(html.all("form#activity_filters > input[type=hidden]", visible: :all).map { |f| f[:id] }.compact).to be_empty
    all_ids = html.all("[id]", visible: :all).map { |node| node[:id] }
    expect(all_ids.uniq.size).to eq(all_ids.size)
  end

  # A submit without a submitter (any control's change) carries these forward.
  # Seeded from the resolved ivars, not raw params, so a custom window survives
  # a Person/Workspace/Kind change.
  it "seeds the band's hidden fields from the resolved filter state" do
    create(:workspace, name: "Alpha")

    get operations_activity_logs_path(range: "custom", from: "2026-09-03", to: "2026-09-17",
                                      direction: "asc", rows: "100")
    html = Capybara.string(response.body)
    hidden = html.all("form#activity_filters > input[type=hidden]", visible: :all)
      .to_h { |field| [ field[:name], field[:value] ] }

    expect(hidden).to include("range" => "custom", "direction" => "asc", "rows" => "100")
    # from/to are NOT hidden fields — the popover's live date inputs carry them,
    # form-associated so they are in every submission the band makes.
    expect(hidden.keys).not_to include("from", "to")
    expect(html.all("input[type=date]", visible: :all).map { |i| [ i[:name], i[:value] ] })
      .to eq([ [ "from", "2026-09-03" ], [ "to", "2026-09-17" ] ])

    # The default window and direction seed nothing — a bare URL stays bare.
    get operations_activity_logs_path
    names = Capybara.string(response.body)
      .all("form#activity_filters > input[type=hidden]", visible: :all).map { |f| f[:name] }
    expect(names).to eq([ "range" ])
  end

  # Without a blank option the combobox can be set but never un-set: once a
  # workspace is chosen there is no option that clears it.
  it "offers a blank option that clears the workspace filter" do
    alpha = create(:workspace, name: "Alpha")

    get operations_activity_logs_path(workspace: alpha.slug)
    options = Capybara.string(response.body)
      .all("[role=listbox] [role=option]", visible: :all)
      .map { |option| [ option[:"data-combobox-value"], option.text ] }

    expect(options.first).to eq([ "", I18n.t("operations.activity_logs.index.filters.workspace_any") ])
    expect(options[1]).to eq([ "instance", I18n.t("operations.activity_logs.index.instance") ])
  end

  # pagy reads `limit` off the query string, so a foreign `limit` riding along
  # on a Rows link wins over `rows` and makes that link's aria-current="true" a
  # lie. ledger_filter_params allow-lists the filter keys for that reason.
  it "keeps foreign query params out of the links it builds" do
    workspace = create(:workspace)
    create(:project, workspace: workspace, name: "Alpha plan")

    get operations_activity_logs_path(limit: "10", foo: "bar", kind: "project")
    rows_links = Capybara.string(response.body)
      .all("nav[aria-label='#{I18n.t('operations.activity_logs.index.rows.label')}'] a")
      .map { |link| link[:href] }

    expect(rows_links.size).to eq(Operations::ActivityLogsController::ROWS.size)
    expect(rows_links).to all(include("kind=project"))
    expect(rows_links.join(" ")).not_to include("limit=")
    expect(rows_links.join(" ")).not_to include("foo=")
  end

  it "paginates through countish so the page param carries the memoized count" do
    workspace = create(:workspace)
    3.times { |i| create(:project, workspace: workspace, name: "Plan #{i}") }

    rows_nav = "nav[aria-label='#{I18n.t('operations.activity_logs.index.rows.label')}']"

    get operations_activity_logs_path(rows: "25")
    html = Capybara.string(response.body)
    expect(html).to have_css("#{rows_nav} a[aria-current='true']", text: "25")
    expect(html).to have_text(I18n.t("operations.activity_logs.index.rows.showing", from: 1, to: ActivityLog.for_operations_feed.count, count: ActivityLog.for_operations_feed.count))

    # The negative control: without it the assertion above passes on a page that
    # marks every Rows link current, which is the same as marking none.
    get operations_activity_logs_path
    html = Capybara.string(response.body)
    expect(html).to have_css("#{rows_nav} a[aria-current='true']", text: Operations::ActivityLogsController::DEFAULT_ROWS)
    expect(html).to have_no_css("#{rows_nav} a[aria-current='true']", text: "25")
  end
  # A discarded workspace's rows can be isolated, and an unresolved slug matches
  # nothing rather than everything (#1170).
  describe "a workspace filter that resolves to nothing" do
    it "answers with the empty state, not with every workspace's rows" do
      other = create(:workspace, name: "Loud Co")
      create(:activity_log, workspace: other, action: "workspace.created", visibility: "workspace")

      get operations_activity_logs_path(workspace: "no-such-slug")

      expect(response.body).to include(I18n.t("operations.activity_logs.index.empty")),
        "an unresolvable slug widened the filter instead of matching nothing"
      expect(response.body).to include("no-such-slug"),
        "the summary dropped the filter instead of naming what was asked for"
    end
  end

  describe "a discarded workspace" do
    it "can be isolated by the filter its rows already appear under" do
      gone = create(:workspace, name: "Folded Co")
      other = create(:workspace, name: "Loud Co")
      create(:activity_log, workspace: gone, action: "workspace.created", visibility: "workspace")
      create(:activity_log, workspace: other, action: "workspace.created", visibility: "workspace")
      gone.discard!

      get operations_activity_logs_path(workspace: gone.slug)

      # Scoped to the table: the picker lists every name.
      rows = Capybara.string(response.body).find("table").text
      expect(rows).to include(gone.name),
        "a discarded workspace's own rows cannot be isolated by its slug"
      expect(rows).not_to include(other.name)
    end
  end
end
