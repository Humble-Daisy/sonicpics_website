require "rails_helper"

RSpec.describe "Operations area", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }
  let(:member) { create(:user) }
  let!(:workspace) { create(:workspace, name: "Acme") }
  let!(:suspended) { create(:workspace, name: "Frozen Co").tap(&:suspend!) }

  it "redirects anonymous visitors to sign in" do
    get operations_root_path
    expect(response).to redirect_to(new_session_path)
  end

  # "Every operations route" means every route, GET and mutating alike —
  # require_operator gates before any action logic runs, so the same 404
  # posture must hold across the whole surface, not just the GETs. The set
  # is derived from the route table rather than hand-listed, so a route
  # added under operations/ without an operator check is caught here without
  # anyone remembering to extend this example.
  it "answers 404 to a signed-in non-operator on every operations route" do
    other_operatorship = Operatorship.grant!(user: create(:user))
    sign_in(member)

    operations_routes = Rails.application.routes.routes.select do |route|
      route.defaults[:controller].to_s.start_with?("operations/")
    end
    # The exact count: an empty selection (a routes.rb typo breaking the
    # scope) and a route quietly removed are both noticed. Update it when the
    # surface changes on purpose.
    expect(operations_routes.size).to eq(16)

    operations_routes.each do |route|
      verb = route.verb.to_s.strip.downcase.to_sym
      controller = route.defaults[:controller]
      action = route.defaults[:action]
      path = route.path.spec.to_s.sub("(.:format)", "")

      route.required_parts.each do |part|
        value = case part
        when :slug, :workspace_slug
          workspace.slug
        when :user_id
          member.id
        when :id
          case controller
          when "operations/operatorships" then other_operatorship.id
          when "operations/users" then member.id
          else
            raise "no resolver for :id on #{controller}##{action} — teach this example its value"
          end
        else
          raise "no resolver for route param :#{part} on #{verb.upcase} #{path} — teach this example its value"
        end
        path = path.sub(":#{part}", value.to_s)
      end

      # A leftover `(` or `:` is an optional segment or an unresolved part;
      # show_exceptions is :rescuable in test, so a path that fails to route
      # would read as the very 404 this example expects.
      expect(path).not_to match(/[(:]/), "unresolved segment in #{verb.upcase} #{path}"
      process(verb, path)
      expect(response).to have_http_status(:not_found),
        "expected 404 for #{verb.upcase} #{path} (#{controller}##{action}), got #{response.status}"
    end
  end

  context "as an operator" do
    before { sign_in(operator) }

    it "lists every kept workspace, suspended ones included and labelled" do
      get operations_workspaces_path
      expect(response).to have_http_status(:ok)
      html = Capybara.string(response.body)
      expect(html).to have_text("Acme")
      expect(html).to have_text("Frozen Co")
      # lifecycle.en.yml roots this key under lifecycle_status, not
      # lifecycle.status. Scoped to the suspended row: have_text alone
      # passes wherever "Locked" appears on the page, so this proves the
      # label belongs to Frozen Co specifically, not merely to the page.
      frozen_row = html.find("tr", text: "Frozen Co")
      expect(frozen_row).to have_text(I18n.t("lifecycle_status.suspended"))
      acme_row = html.find("tr", text: "Acme")
      expect(acme_row).not_to have_text(I18n.t("lifecycle_status.suspended"))
    end

    it "never establishes a workspace context" do
      # A spy on the setter, not a post-hoc read:
      # ActiveSupport::CurrentAttributes is reset by the executor at the end
      # of every request, so Current.workspace already reads nil after ANY
      # request whether or not this controller ever assigned it — a
      # post-hoc read against a workspace-scoped route would pass
      # vacuously. Observing the request in flight is the only way this
      # assertion can fail on a direct assignment.
      allow(Current).to receive(:workspace=).and_call_original
      get operations_workspaces_path
      expect(Current).not_to have_received(:workspace=)
      expect(session[:current_workspace_id]).to be_nil
    end

    it "reaches the area with onboarding incomplete rather than being funneled into the wizard" do
      # RequiresOnboarding#require_onboarding only funnels under the :none
      # preset (config/initializers/tenancy.rb) — the default :personal
      # preset makes this guard inert regardless of skip_onboarding_requirement,
      # so exercising it here means the example proves the class method is
      # doing real work, not asserting an already-inert path.
      allow(TenancyConfig).to receive(:onboarding).and_return(:none)
      operator.update!(onboarded_at: nil)
      get operations_workspaces_path
      expect(response).to have_http_status(:ok)
    end

    it "lets an un-onboarded operator finish reauthentication and land back on /operations" do
      allow(TenancyConfig).to receive(:onboarding).and_return(:none)
      operator.update!(onboarded_at: nil)
      operator.sessions.update_all(reauthenticated_at: nil)

      get operations_workspaces_path
      expect(response).to redirect_to(new_settings_reauthentication_path)

      get new_settings_reauthentication_path
      expect(response).to have_http_status(:ok)

      post settings_reauthentication_path, params: { password: "SecureP@ssw0rd123!" }
      expect(response).to redirect_to(operations_workspaces_path)
    end

    it "requires a fresh reauthentication" do
      operator.sessions.update_all(reauthenticated_at: nil)
      get operations_workspaces_path
      expect(response).to redirect_to(new_settings_reauthentication_path)
      expect(session[:return_to_after_reauthentication]).to eq(operations_workspaces_path)
    end

    describe "reauthentication gate is hard-wired" do
      # force: true (base_controller.rb) is the guarantee this gate survives
      # a fork disabling reauth — same rule and proving pattern as passkey
      # enrollment (spec/requests/passkeys/registration_ceremony_spec.rb).
      # With reauth_enabled true (the test default) the ordinary branch
      # already fires regardless of force:, so only flipping the flag off
      # can catch force: silently dropped to false.
      around do |example|
        original = Rails.configuration.x.session.reauth_enabled
        Rails.configuration.x.session.reauth_enabled = false
        example.run
      ensure
        Rails.configuration.x.session.reauth_enabled = original
      end

      it "still requires a fresh factor to enter the area when reauth_enabled is false" do
        operator.sessions.update_all(reauthenticated_at: nil)
        get operations_workspaces_path
        expect(response).to redirect_to(new_settings_reauthentication_path)
      end
    end

    # Rails routes HEAD to the GET action, but request.get? is false for
    # HEAD — so a get?-only check would silently take the referer-path
    # branch instead of the GET-correct one. Brakeman's VerbConfusion check
    # is what catches that shape; it is not an rspec-visible bug.
    it "treats a HEAD request like the GET it is routed as" do
      operator.sessions.update_all(reauthenticated_at: nil)
      head operations_workspaces_path
      expect(session[:return_to_after_reauthentication]).to eq(operations_workspaces_path)
    end

    # The statement shares the nav row now instead of owning a boxed band, but
    # it stays a named landmark — that is what lets a screen-reader user jump
    # to "where am I" without reading the nav. Both halves asserted: a <p> that
    # lost role=region would still pass a text-only check.
    it "renders the operations banner as a named landmark so the area is unmistakable" do
      get operations_workspaces_path
      html = Capybara.string(response.body)
      expect(html).to have_text(I18n.t("operations.area.banner"))
      expect(html).to have_css(%(p[role="region"][aria-label="#{I18n.t("operations.area.banner_label")}"]),
        text: I18n.t("operations.area.banner"))
    end

    # The same preflight list-style:none trap as the activity feed's <ol> —
    # this <ul> is the area's other raw list.
    it "restores list semantics on the nav's raw <ul>" do
      get operations_workspaces_path
      expect(Capybara.string(response.body)).to have_css('nav ul[role="list"]')
    end

    # The fork seam: a fork's pages join the nav after the template's, with the same current-page cue.
    # allow_any_instance_of because the view context is built per request.
    it "appends the fork's nav items after the template's" do
      allow_any_instance_of(Operations::ForkNavHelper)
        .to receive(:operations_fork_nav_items).and_return([ [ "Fork page", operations_users_path ] ])

      get operations_users_path

      links = Capybara.string(response.body).all("nav ul li a")
      expect(links.map(&:text).last).to eq("Fork page")
      expect(links.select { |link| link[:"aria-current"] == "page" }.map(&:text)).to include("Fork page")
    end

    it "adds no nav items of its own when the fork lists none" do
      get operations_workspaces_path

      expect(Capybara.string(response.body).all("nav ul li").size).to eq(4)
    end

    # WCAG 2.4.8 Location (AAA, outside the axe tag set). The cue matches
    # shared/_settings_sidebar_item — a filled surface, a weight bump and a
    # heading-colour shift together — rather than weight alone: this app's
    # other horizontal navs all use that treatment, and one step of weight at
    # 14px is a weak signal on its own. text-text-heading on bg-surface-sunken
    # is a proven AAA pairing (tokens/_semantic.css, ~21:1).
    it "marks the current page in the nav with aria-current and the house visible cue" do
      get operations_workspaces_path
      html = Capybara.string(response.body)

      current_link = html.find("nav a", text: I18n.t("operations.nav.workspaces"))
      expect(current_link["aria-current"]).to eq("page")
      expect(current_link[:class]).to include("bg-surface-sunken", "font-semibold", "text-text-heading")

      other_link = html.find("nav a", text: I18n.t("operations.nav.users"))
      expect(other_link["aria-current"]).to be_nil
      expect(other_link[:class]).not_to include("bg-surface-sunken")
    end

    # .btn-text sets no colour of its own — .btn-text-interactive is what
    # makes a nav link read as a link rather than plain text (1.4.1). Both
    # states carry it; text-text-heading (a Tailwind utility, compiled after
    # .btn-text-interactive's components-layer rule) is what still wins the
    # current page's colour — verified against the compiled stylesheet, not
    # asserted here since cascade order isn't request-spec-observable.
    it "keeps the link colour on every nav item, current page included" do
      get operations_workspaces_path
      html = Capybara.string(response.body)
      operations_nav = html.find("nav[aria-label='#{I18n.t('operations.area.nav_label')}']")

      operations_nav.all("a").each do |link|
        expect(link[:class]).to include("btn-text-interactive")
      end
    end
  end
end
