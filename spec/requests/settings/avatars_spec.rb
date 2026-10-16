require "rails_helper"

RSpec.describe "Account Avatars", type: :request do
  describe "unauthenticated access" do
    it "redirects PATCH /account/avatar to sign in" do
      patch settings_avatar_path
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects DELETE /account/avatar to sign in" do
      delete settings_avatar_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    describe "the profile page's Remove photo button" do
      it "removes the avatar" do
        get edit_settings_profile_path

        # The crop section renders `hidden` until a photo is chosen.
        remove = Capybara.string(response.body).find("form", text: I18n.t("identity_picker.remove_photo"), visible: :all)
        expect(remove[:action]).to eq(settings_avatar_path)
        expect(remove).to have_field("_method", type: :hidden, with: "delete", visible: :all)
      end
    end

    describe "PATCH /account/avatar" do
      it "uploads an avatar and redirects to profile edit page" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch settings_avatar_path, params: { avatar: file }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_source).to eq("upload")
        expect(response).to redirect_to(edit_settings_profile_path)
        expect(flash[:notice]).to eq(I18n.t("settings.avatars.update.success"))
      end

      it "rejects invalid content type" do
        file = Rack::Test::UploadedFile.new(
          StringIO.new("not an image"), "text/plain", true, original_filename: "document.txt"
        )
        patch settings_avatar_path, params: { avatar: file }
        expect(response).to redirect_to(edit_settings_profile_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.avatar).not_to be_attached
      end

      it "rejects oversized file" do
        large_io = StringIO.new("x" * 6.megabytes)
        file = Rack::Test::UploadedFile.new(
          large_io, "image/png", true, original_filename: "oversized.png"
        )
        patch settings_avatar_path, params: { avatar: file }
        expect(response).to redirect_to(edit_settings_profile_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.avatar).not_to be_attached
      end

      it "changes avatar source without uploading a file" do
        user.update_columns(has_gravatar: true)
        patch settings_avatar_path, params: { avatar_source: "gravatar" }
        expect(user.reload.avatar_source).to eq("gravatar")
        expect(response).to redirect_to(edit_settings_profile_path)
      end

      it "rejects invalid avatar source" do
        patch settings_avatar_path, params: { avatar_source: "invalid" }
        expect(response).to redirect_to(edit_settings_profile_path)
        expect(flash[:alert]).to eq(I18n.t("settings.avatars.source_unavailable"))
      end

      it "returns a 403 turbo-stream toast for an invalid source (unified with workspaces)" do
        patch settings_avatar_path, params: { avatar_source: "invalid" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:forbidden)
        expect(response.body).to include(I18n.t("settings.avatars.source_unavailable"))
      end

      it "accepts upload source even when no avatar is attached" do
        patch settings_avatar_path, params: { avatar_source: "upload" }
        expect(response).to redirect_to(edit_settings_profile_path)
        expect(flash[:alert]).to be_nil
        expect(user.reload.avatar_source).to eq("upload")
      end

      it "rejects gravatar source when user has no Gravatar" do
        user.update_columns(has_gravatar: false)
        patch settings_avatar_path, params: { avatar_source: "gravatar" }
        expect(response).to redirect_to(edit_settings_profile_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.avatar_source).to eq("initials")
      end

      it "redirects when no params provided" do
        patch settings_avatar_path
        expect(response).to redirect_to(edit_settings_profile_path)
      end

      it "prioritizes file upload when both file and source are provided" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch settings_avatar_path, params: { avatar: file, avatar_source: "gravatar" }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_source).to eq("upload")
      end
    end

    describe "PATCH /account/avatar with primary_color" do
      it "updates primary_color when switching to initials" do
        patch settings_avatar_path, params: { avatar_source: "initials", primary_color: "270" }
        expect(user.reload.primary_color).to eq(270)
        expect(user.avatar_source).to eq("initials")
      end
    end

    describe "PATCH /account/avatar with cropped image" do
      it "saves both avatar and avatar_original" do
        cropped = fixture_file_upload("avatar.png", "image/png")
        original = fixture_file_upload("avatar.png", "image/png")
        patch settings_avatar_path, params: {
          avatar: cropped,
          avatar_original: original,
          avatar_source: "upload",
          crop_coordinates: '{"x":10,"y":20,"w":100,"h":100}'
        }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_original).to be_attached
        expect(user.avatar_source).to eq("upload")
        metadata = user.avatar_original.blob.metadata
        expect(metadata["crop"]).to eq("x" => 10, "y" => 20, "w" => 100, "h" => 100)
      end
    end

    describe "PATCH /account/avatar (turbo_stream)" do
      it "responds with turbo stream that updates avatars and closes modal" do
        patch settings_avatar_path, params: { avatar_source: "initials", primary_color: "180" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("user_avatar_profile")
        expect(response.body).to include("user_avatar_header")
        expect(response.body).to include("modal-closer")
      end
    end

    context "when avatar_source changes to initials (photo removal)" do
      before do
        user.avatar.attach(fixture_file_upload("avatar.png", "image/png"))
        user.avatar_original.attach(fixture_file_upload("avatar.png", "image/png"))
        user.update!(avatar_source: "upload")
      end

      it "purges avatar attachments and switches source to initials" do
        patch settings_avatar_path, params: {
          avatar_source: "initials"
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.status).to be < 400
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_original).not_to be_attached
        expect(user.avatar_source).to eq("initials")
      end
    end

    describe "PATCH /account/avatar crop save vs hub save" do
      it "does NOT close modal when saving a crop (file present)" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch settings_avatar_path, params: { avatar: file, avatar_source: "upload" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.body).not_to include("modal-closer")
        expect(response.body).to include("user_avatar_profile")
      end

      it "closes modal when saving source change (no file)" do
        patch settings_avatar_path, params: { avatar_source: "initials" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.body).to include("modal-closer")
      end
    end

    describe "PATCH /account/avatar re-crop" do
      it "saves avatar without avatar_original on re-crop" do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
        user.avatar_original.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "original.png", content_type: "image/png"
        )
        new_crop = fixture_file_upload("avatar.png", "image/png")
        patch settings_avatar_path, params: {
          avatar: new_crop,
          crop_coordinates: '{"x":20,"y":30,"w":50,"h":50}'
        }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_original).to be_attached
        metadata = user.avatar_original.blob.metadata
        expect(metadata["crop"]).to eq("x" => 20, "y" => 30, "w" => 50, "h" => 50)
      end
    end

    describe "PATCH /account/avatar with crop_coordinates edge cases" do
      context "with malformed JSON" do
        it "ignores malformed JSON without crashing" do
          file = fixture_file_upload("avatar.png", "image/png")
          patch settings_avatar_path, params: {
            avatar: file,
            avatar_original: file,
            crop_coordinates: "not-valid-json{",
            avatar_source: "upload"
          }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          expect(response.status).to be < 500
        end
      end

      context "with valid coords" do
        it "stores coords when they have the expected shape" do
          file = fixture_file_upload("avatar.png", "image/png")
          patch settings_avatar_path, params: {
            avatar: file,
            avatar_original: file,
            crop_coordinates: '{"x":10,"y":20,"w":100,"h":100}',
            avatar_source: "upload"
          }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          user.reload
          expect(user.avatar_original.blob.metadata["crop"]).to eq({ "x" => 10, "y" => 20, "w" => 100, "h" => 100 })
        end
      end
    end

    context "when save fails during avatar update" do
      # Trigger a real validation failure by sending an out-of-range primary_color.
      # User validates primary_color inclusion in 0..360, so 999 is always invalid.
      let(:invalid_color) { 999 }

      it "returns 422 turbo stream for turbo_stream requests (not a redirect)" do
        patch settings_avatar_path, params: {
          avatar_source: "initials",
          primary_color: invalid_color
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "still redirects for non-turbo HTML requests" do
        patch settings_avatar_path, params: {
          avatar_source: "initials",
          primary_color: invalid_color
        }

        expect(response).to have_http_status(:redirect)
      end

      it "purges the newly attached avatar and original when save fails" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch settings_avatar_path, params: {
          avatar: file, avatar_original: file, primary_color: invalid_color
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:unprocessable_content)
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_original).not_to be_attached
      end

      context "with an existing avatar" do
        let(:user) { create(:user, :with_avatar) }

        it "keeps the prior avatar when a replacement fails (single-save)" do
          old_blob_id = user.avatar.blob.id
          patch settings_avatar_path, params: {
            avatar: fixture_file_upload("avatar.png", "image/png"),
            primary_color: invalid_color
          }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          user.reload
          expect(user.avatar).to be_attached
          expect(user.avatar.blob.id).to eq(old_blob_id)
        end
      end
    end

    describe "DELETE /account/avatar rate limiting" do
      it "returns 429 once the shared avatar limit is exceeded" do
        # rate_limit counts via Rails.cache.increment; return an over-limit
        # count so the limiter fires without a persistent cache (house pattern,
        # see passkeys/authentications_spec).
        allow(Rails.cache).to receive(:increment).and_return(21)

        delete settings_avatar_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:too_many_requests)
        expect(response.body).to include(I18n.t("settings.avatars.update.rate_limited"))
        expect(user.reload.avatar_source).not_to be_nil
      end
    end

    describe "DELETE /account/avatar" do
      it "removes the avatar and falls back to initials" do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png",
          content_type: "image/png"
        )
        user.update_columns(avatar_source: "upload")
        delete settings_avatar_path
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_source).to eq("initials")
        expect(response).to redirect_to(edit_settings_profile_path)
        expect(flash[:notice]).to eq(I18n.t("settings.avatars.destroy.success"))
      end

      it "handles destroy gracefully when no avatar is attached" do
        delete settings_avatar_path
        expect(user.reload.avatar_source).to eq("initials")
        expect(response).to redirect_to(edit_settings_profile_path)
      end
    end

    describe "DELETE /account/avatar (turbo_stream)" do
      before do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png",
          content_type: "image/png"
        )
        user.update!(avatar_source: "upload")
      end

      it "responds with turbo stream" do
        delete settings_avatar_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_source).to eq("initials")
      end

      it "still redirects for HTML requests" do
        delete settings_avatar_path
        expect(response).to redirect_to(edit_settings_profile_path)
      end

      it "renders an error toast when the save fails (invalid persisted state)" do
        user.update_columns(primary_color: 999)
        delete settings_avatar_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("toast-cards")
        user.reload
        # Purge precedes the failed save (design-documented parity): blobs are
        # gone but the source column keeps its old value.
        expect(user.avatar).not_to be_attached
        expect(user.avatar_source).to eq("upload")
      end
    end

    describe "authorization" do
      it "invokes Settings::AvatarPolicy#update? via Pundit" do
        real_policy = nil
        allow(Settings::AvatarPolicy).to receive(:new).and_wrap_original do |orig, *args|
          real_policy = orig.call(*args)
          allow(real_policy).to receive(:update?).and_call_original
          real_policy
        end

        patch settings_avatar_path, params: { avatar_source: "initials" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(real_policy).to have_received(:update?)
      end
    end

    describe "GET /settings/profile (identity picker crop controls)" do
      it "renders the crop reset/cancel/save through btn utilities (icon-text pair excluded, #760)" do
        get edit_settings_profile_path
        html = Capybara.string(response.body)
        expect(html).to have_css("button.btn-secondary.w-full", text: I18n.t("identity_picker.reset_crop"), visible: :all)
        expect(html).to have_css("button.btn-secondary", text: I18n.t("identity_picker.cancel"), visible: :all)
        expect(html).to have_css("button.btn-primary", text: I18n.t("identity_picker.save_crop"), visible: :all)
        # Guards (green before and after): the two icon+label text buttons stay hand-rolled (#760).
        expect(html).to have_no_css("button.btn-text", text: I18n.t("identity_picker.upload_new"), visible: :all)
        expect(html).to have_no_css("button.btn-text", text: I18n.t("identity_picker.remove_photo"), visible: :all)
      end
    end

    # The picker hub is the avatar resource's show (#1007); it was GET /hub.
    describe "GET /account/avatar" do
      it "renders the hub partial" do
        get settings_avatar_path(source: "initials"),
          headers: { "Turbo-Frame" => "identity-picker-hub" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("identity-picker-hub")
      end

      it "falls back to current source for invalid source param" do
        get settings_avatar_path(source: "invalid"),
          headers: { "Turbo-Frame" => "identity-picker-hub" }

        expect(response).to have_http_status(:ok)
      end
    end

    context "avatar_source guard on file upload" do
      let(:valid_avatar) { fixture_file_upload("avatar.png", "image/png") }

      before do
        # Simulate a user whose available sources don't include "upload".
        # available_avatar_sources hardcodes "upload" (User#available_avatar_sources),
        # so there is no real-data path that excludes it. Route the controller's
        # Current.user to this signed-in user (a single class-level seam) and stub
        # the one method on that real object — `allow` on a real instance still
        # verifies the method exists, unlike allow_any_instance_of.
        allow(Current).to receive(:user).and_return(user)
        allow(user).to receive(:available_avatar_sources).and_return(%w[gravatar initials])
      end

      it "rejects file upload when upload is not an allowed source" do
        patch settings_avatar_path, params: {
          avatar: valid_avatar,
          avatar_original: valid_avatar,
          avatar_source: "upload"
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_original).not_to be_attached
      end
    end

    describe "DELETE /account/avatar purges original" do
      it "purges both avatar and avatar_original" do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
        user.avatar_original.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "original.png", content_type: "image/png"
        )
        user.update_columns(avatar_source: "upload")
        delete settings_avatar_path
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_original).not_to be_attached
      end
    end
  end
end
