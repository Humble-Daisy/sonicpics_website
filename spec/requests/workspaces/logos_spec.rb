require "rails_helper"

# A singular logo resource: show is the picker hub (#1007), destroy removes the logo (#1402);
# saves post to workspaces#update, where the logo lives.
RSpec.describe "Workspace Logo", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/logo to sign in" do
      get workspace_logo_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects DELETE /workspaces/:slug/logo to sign in" do
      delete workspace_logo_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }
    let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

    before { sign_in(user) }

    describe "GET /workspaces/:slug/logo" do
      it "renders the picker hub partial" do
        get workspace_logo_path(workspace, source: "initials"),
            headers: { "Turbo-Frame" => "identity-picker-hub" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("identity-picker-hub")
      end

      it "falls back to the current logo source for an invalid source param" do
        get workspace_logo_path(workspace, source: "gravatar"),
            headers: { "Turbo-Frame" => "identity-picker-hub" }
        expect(response).to have_http_status(:ok)
      end

      it "denies a member without manage_settings" do
        member = create(:user)
        create(:membership, user: member, workspace: workspace)
        sign_in(member)
        get workspace_logo_path(workspace)
        expect(response).not_to have_http_status(:ok)
      end
    end

    describe "DELETE /workspaces/:slug/logo" do
      let(:workspace) { create(:workspace, :with_logo) }

      it "removes the logo and keeps the workspace" do
        delete workspace_logo_path(workspace), headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        workspace.reload
        expect(workspace.discarded_at).to be_nil
        expect(workspace.logo_source).to eq("initials")
        expect(workspace.logo).not_to be_attached
        expect(workspace.logo_original).not_to be_attached
      end

      it "refreshes the Profile and switcher logos and closes the picker" do
        delete workspace_logo_path(workspace), headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("workspace_logo_branding")
        expect(response.body).to include("workspace-switcher-button")
        expect(response.body).to include("workspace-switcher-button-mobile")
        expect(response.body).to include("modal-closer")
        expect(response.body).to include(I18n.t("workspaces.logos.destroy.success"))
      end

      it "redirects an HTML request back to the Profile page" do
        delete workspace_logo_path(workspace)

        expect(response).to redirect_to(edit_workspace_path(workspace))
        expect(workspace.reload.discarded_at).to be_nil
      end

      it "renders an error toast and keeps the workspace when the save fails" do
        workspace.update_columns(primary_color: 999)

        delete workspace_logo_path(workspace), headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("Primary color is not included in the list")
        expect(workspace.reload.discarded_at).to be_nil
      end

      it "tells an HTML request why the save failed" do
        workspace.update_columns(primary_color: 999)

        delete workspace_logo_path(workspace)

        expect(response).to redirect_to(edit_workspace_path(workspace))
        expect(flash[:alert]).to eq("Primary color is not included in the list")
      end

      it "returns 429 once the limit is exceeded" do
        # rate_limit counts via Rails.cache.increment; an over-limit count fires it without a real cache.
        allow(Rails.cache).to receive(:increment).and_return(21)

        delete workspace_logo_path(workspace), headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:too_many_requests)
        expect(response.body).to include(I18n.t("workspaces.update.rate_limited"))
        expect(workspace.reload.logo).to be_attached
      end

      it "denies a member without manage_settings and leaves the logo alone" do
        member = create(:user)
        create(:membership, user: member, workspace: workspace)
        sign_in(member)

        delete workspace_logo_path(workspace)

        expect(response).not_to have_http_status(:ok)
        expect(workspace.reload.logo_source).to eq("upload")
        expect(workspace.logo).to be_attached
      end
    end

    describe "the Profile page's Remove photo button" do
      it "removes the logo, never the workspace" do
        get edit_workspace_path(workspace)

        # The crop section renders `hidden` until a photo is chosen.
        remove = Capybara.string(response.body).find("form", text: I18n.t("identity_picker.remove_photo"), visible: :all)
        expect(remove[:action]).to eq(workspace_logo_path(workspace))
        expect(remove).to have_field("_method", type: :hidden, with: "delete", visible: :all)
      end
    end
  end
end
