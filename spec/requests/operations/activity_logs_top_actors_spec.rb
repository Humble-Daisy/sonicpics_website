require "rails_helper"

# "Who has been busiest here" is usually the first question an operator asks of a
# filtered window, and the ledger could not answer it. Sorting by Who was ruled
# out — actor names are encrypted, so SQL cannot order them — and a sort answers
# the question badly anyway: it clusters names alphabetically and then asks you to
# eyeball which block is tallest, across pages. A count states it.
#
# The strip is a grouped count over the SAME filtered scope the table uses, on an
# indexed integer column. That is what makes it uncapped and correct: it counts
# every matching row, not the rows that happen to be on this page, and only the
# handful of names actually shown are decrypted.
RSpec.describe "Operations activity ledger top actors", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in(operator) }

  def strip(body) = Capybara.string(body).find("[data-role=top-actors]", visible: :all)
  def entries(body) = strip(body).all("[data-role=top-actor]", visible: :all)

  # Renames, not creations: a workspace has a project limit, and a rename is the
  # cheapest way to mint an attributed row. Each rename is exactly one activity
  # row actored by `user`, so the count the strip shows is `times`.
  def busy(user, workspace, times, project: nil)
    project ||= create(:project, workspace: workspace)
    acting_as(user) { times.times { |i| project.update!(name: "P#{user.id}-#{i}") } }
    project
  end

  it "names the busiest people for the current filter, with their counts" do
    workspace = create(:workspace)
    ada = create(:user, first_name: "Ada", last_name: "Lovelace")
    grace = create(:user, first_name: "Grace", last_name: "Hopper")
    busy(ada, workspace, 3)
    busy(grace, workspace, 1)

    get operations_activity_logs_path

    expect(entries(response.body).first.text).to include("Ada Lovelace")
    expect(entries(response.body).first.text).to match(/\b3\b/)
  end

  # The property that makes this worth building rather than counting the page:
  # the count is of everything that matched, not of what fitted on the screen.
  it "counts every matching row, not the rows on this page" do
    workspace = create(:workspace)
    ada = create(:user, first_name: "Ada", last_name: "Lovelace")
    busy(ada, workspace, 30)
    total = ActivityLog.where(actor_id: ada.id).count

    get operations_activity_logs_path(rows: "25")
    shown = Capybara.string(response.body).all("tbody tr").size

    expect(total).to be > shown
    expect(entries(response.body).first.text).to include(total.to_s)
  end

  it "moves with the filter rather than describing the whole instance" do
    here = create(:workspace, name: "Here")
    elsewhere = create(:workspace, name: "Elsewhere")
    ada = create(:user, first_name: "Ada", last_name: "Lovelace")
    grace = create(:user, first_name: "Grace", last_name: "Hopper")
    busy(ada, here, 1)
    busy(grace, elsewhere, 3)

    get operations_activity_logs_path(workspace: here.slug)

    expect(strip(response.body).text).to include("Ada Lovelace")
    expect(strip(response.body).text).not_to include("Grace Hopper")
  end

  # "System" is not a who. Rows with no actor are jobs, the console or seeds, and
  # counting them would answer a different question than the one being asked.
  it "leaves actorless rows out — the strip answers who, and System is not a who" do
    workspace = create(:workspace)
    ada = create(:user, first_name: "Ada", last_name: "Lovelace")
    busy(ada, workspace, 1)
    create(:project, workspace: workspace).update!(name: "Unattributed") # no Current.user

    get operations_activity_logs_path

    expect(strip(response.body).text).to include("Ada Lovelace")
    expect(strip(response.body).text).not_to include(I18n.t("operations.activity_logs.index.system"))
  end

  it "shows only the few busiest, not everyone who appears" do
    workspace = create(:workspace)
    stub_const("Operations::ActivityLogsController::TOP_ACTORS", 2)
    project = create(:project, workspace: workspace)
    3.times { |i| busy(create(:user, first_name: "P#{i}", last_name: "Erson"), workspace, i + 1, project: project) }

    get operations_activity_logs_path

    expect(entries(response.body).size).to eq(2)
  end

  # A deleted actor claimed a slot and then vanished, shortening the strip (#1250).
  it "stays full when one of the busiest has since been deleted" do
    workspace = create(:workspace)
    stub_const("Operations::ActivityLogsController::TOP_ACTORS", 2)
    project = create(:project, workspace: workspace)
    departing = create(:user, first_name: "Gone", last_name: "Away")
    busy(departing, workspace, 9, project: project)
    2.times { |i| busy(create(:user, first_name: "Still#{i}", last_name: "Here"), workspace, i + 1, project: project) }

    departing.destroy!
    get operations_activity_logs_path

    expect(entries(response.body).size).to eq(2)
    expect(strip(response.body).text).to include("Still0 Here", "Still1 Here")
    expect(strip(response.body).text).not_to include("Gone Away")
  end

  # A way INTO the ledger, not a decoration on top of it — and through the same
  # pivot the row details already use, so there is one way to narrow to a person.
  it "makes each entry filter to that person" do
    workspace = create(:workspace)
    ada = create(:user, first_name: "Ada", last_name: "Lovelace")
    busy(ada, workspace, 1)

    get operations_activity_logs_path
    link = entries(response.body).first.find("a", visible: :all)

    expect(link[:href]).to include(CGI.escape(ada.email_address))
    expect(link["data-turbo-frame"]).to eq("_top")
    expect(link[:"aria-label"]).to contain_visible_text(link.text)
  end

  it "says nothing at all when no row has an actor" do
    workspace = create(:workspace)
    create(:project, workspace: workspace).update!(name: "Unattributed")

    get operations_activity_logs_path

    expect(response.body).not_to include("data-role=\"top-actors\"")
  end

  it "says nothing when the filter matched no rows" do
    create(:workspace)

    get operations_activity_logs_path(q: "nobody@example.com")

    expect(response.body).not_to include("data-role=\"top-actors\"")
  end
end
