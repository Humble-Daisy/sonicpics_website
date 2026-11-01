require "rails_helper"

# The workspace filter's reach is `Workspace.kept` — EVERY workspace on the
# instance — so its option list grows with the tenant count, which is the number
# this template exists to grow. Rendering all of them into the filter band put a
# payload on every full-page navigation (sorting and paging both are) that scaled
# with the business.
#
# Above a threshold the control stops being a list and becomes a search. The
# threshold matters because this is a FORK TEMPLATE: nobody is watching a given
# fork's instance to notice the day it crosses the line, so the page has to cross
# it by itself.
#
# Truncating the list silently is NOT the fix and must never become it: a
# workspace missing from a capped list is unselectable with no signal. Every
# example here that caps something also asserts the page SAYS it capped.
RSpec.describe "Operations activity ledger workspace picker", type: :request do
  # Fixed, because the operator's own "<first name>'s Workspace" is searchable too (a random Ralph matched "alph").
  let(:operator) { create(:user, first_name: "Operator").tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in(operator) }

  # Two is enough to be "over the limit" once the limit is 1 — the boundary is
  # what matters, not the magnitude.
  def small_instance = stub_const("Operations::ActivityLogsController::WORKSPACE_PICKER_LIMIT", 50)
  def large_instance = stub_const("Operations::ActivityLogsController::WORKSPACE_PICKER_LIMIT", 1)

  def picker(body) = Capybara.string(body).find("[data-filter=workspace]", visible: :all)

  # --- the small path: unchanged ------------------------------------------

  it "renders every workspace as an option while the instance is small" do
    create(:workspace, name: "Alpha")
    create(:workspace, name: "Beta")
    small_instance

    get operations_activity_logs_path

    expect(response.body).to include("Alpha").and include("Beta")
    expect(picker(response.body)).to have_css("[role=option]", visible: :all)
  end

  # --- the large path: no option list at all -------------------------------

  it "stops rendering the option list once the instance is over the limit" do
    create(:workspace, name: "Alpha")
    create(:workspace, name: "Beta")
    create(:workspace, name: "Gamma")
    large_instance

    get operations_activity_logs_path

    # Scoped to the picker on purpose: the names still appear in the ledger's
    # own rows, which is not the payload this is about.
    expect(picker(response.body)).to have_no_css("[role=option]", visible: :all)
    expect(picker(response.body).text).not_to include("Gamma")
  end

  it "offers a search control instead" do
    create_list(:workspace, 2)
    large_instance

    get operations_activity_logs_path

    expect(picker(response.body)).to have_css("input[name=workspace_q]", visible: :all)
  end

  # --- searching -----------------------------------------------------------

  it "applies the filter when a search names exactly one workspace" do
    alpha = create(:workspace, name: "Alpha")
    create(:workspace, name: "Beta")
    create(:project, workspace: alpha).update!(name: "Alpha plan")
    large_instance

    get operations_activity_logs_path(workspace_q: "alph")

    expect(response.body).to include("Alpha plan")
    expect(picker(response.body)).to have_no_css("[data-role=workspace-candidate]", visible: :all)
  end

  it "offers the choices instead of guessing when a search names several" do
    create(:workspace, name: "Acme North")
    create(:workspace, name: "Acme South")
    large_instance

    get operations_activity_logs_path(workspace_q: "acme")
    candidates = picker(response.body).all("[data-role=workspace-candidate]", visible: :all)

    expect(candidates.map(&:text)).to contain_exactly("Acme North", "Acme South")
  end

  it "says so when a search names nothing, rather than looking like an empty filter" do
    create(:workspace, name: "Alpha")
    large_instance

    get operations_activity_logs_path(workspace_q: "nothing-matches-this")

    expect(picker(response.body).text).to include(
      I18n.t("operations.activity_logs.index.filters.workspace_no_match", query: "nothing-matches-this")
    )
  end

  # A capped candidate list is honest about being capped — the alternative is a
  # user hunting for a workspace the page decided not to mention.
  it "caps the candidate list and says that it did" do
    create_list(:workspace, 3) { |w, i| w.update!(name: "Acme #{i}") }
    large_instance
    stub_const("Operations::ActivityLogsController::WORKSPACE_CANDIDATE_LIMIT", 2)

    get operations_activity_logs_path(workspace_q: "acme")

    expect(picker(response.body).all("[data-role=workspace-candidate]", visible: :all).size).to eq(2)
    expect(picker(response.body).text).to include(
      I18n.t("operations.activity_logs.index.filters.workspace_more", count: 3, shown: 2)
    )
  end

  # --- the shareable URL keeps working -------------------------------------

  it "still filters by slug on the large path, so existing links keep working" do
    alpha = create(:workspace, name: "Alpha")
    beta = create(:workspace, name: "Beta")
    create(:project, workspace: alpha).update!(name: "Alpha plan")
    create(:project, workspace: beta).update!(name: "Beta plan")
    large_instance

    get operations_activity_logs_path(workspace: alpha.slug)

    expect(response.body).to include("Alpha plan")
    expect(response.body).not_to include("Beta plan")
  end

  it "names the applied workspace on the large path, where no option list can show it" do
    alpha = create(:workspace, name: "Alpha")
    create_list(:workspace, 2)
    large_instance

    get operations_activity_logs_path(workspace: alpha.slug)

    expect(picker(response.body).text).to include("Alpha")
  end

  it "keeps the instance-level choice reachable on both paths" do
    create_list(:workspace, 2)
    Operatorship.grant!(user: create(:user, first_name: "Gale", last_name: "Grantee"))
    large_instance

    get operations_activity_logs_path(workspace: "instance")

    expect(response.body).to include("granted Gale Grantee operator access")
  end
  # --- the invariant a fork depends on --------------------------------------

  # The one property that must hold at any instance size, and the reason the
  # threshold exists at all: the band never renders an unbounded option list.
  # A fork that grows past the limit gets the search shape without its author
  # doing anything, because no author is watching for the day it happens.
  it "never renders more workspace options than the limit, whatever the instance size" do
    create_list(:workspace, 5)
    stub_const("Operations::ActivityLogsController::WORKSPACE_PICKER_LIMIT", 3)

    get operations_activity_logs_path
    options = picker(response.body).all("[role=option]", visible: :all)

    expect(Workspace.kept.count).to be > Operations::ActivityLogsController::WORKSPACE_PICKER_LIMIT
    expect(options.size).to be <= Operations::ActivityLogsController::WORKSPACE_PICKER_LIMIT
  end
end
