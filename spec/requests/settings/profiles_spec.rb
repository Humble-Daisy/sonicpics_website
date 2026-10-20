require "rails_helper"

RSpec.describe "Account Profiles", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /account/profile/edit to sign in" do
      get edit_settings_profile_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    describe "GET /account/profile/edit" do
      it "renders the edit form" do
        get edit_settings_profile_path
        expect(response).to have_http_status(:ok)
      end

      it "names the avatar button with the initials it shows (WCAG 2.5.3 Label in Name)" do
        get edit_settings_profile_path
        button = Capybara.string(response.body).find("button:has(#user_avatar_profile)")
        expect(button[:"aria-label"]).to contain_visible_text(button.text).and include(user.initials)
      end
    end

    describe "PATCH /account/profile" do
      context "name change only (no email change)" do
        it "updates the name without requiring password" do
          patch settings_profile_path, params: {
            user: { first_name: "Updated", last_name: "Name" }
          }
          expect(user.reload.first_name).to eq("Updated")
          expect(response).to redirect_to(edit_settings_profile_path)
        end
      end

      context "email change with correct password" do
        it "sets pending email and sends verification" do
          expect {
            patch settings_profile_path, params: {
              user: { email_address: "new@example.com", current_password: "SecureP@ssw0rd123!" }
            }
          }.to have_enqueued_mail(AuthenticationMailer, :email_change_verification)

          expect(user.reload.pending_email).to eq("new@example.com")
          expect(user.email_address).not_to eq("new@example.com")
          expect(response).to redirect_to(edit_settings_profile_path)
          expect(flash[:notice]).to eq(I18n.t("settings.profiles.update.verification_sent", email: "new@example.com"))
        end

        it "sends notification to old email" do
          expect {
            patch settings_profile_path, params: {
              user: { email_address: "new@example.com", current_password: "SecureP@ssw0rd123!" }
            }
          }.to have_enqueued_mail(AuthenticationMailer, :email_change_notification)
        end

        it "redirects with verification notice" do
          patch settings_profile_path, params: {
            user: { email_address: "new@example.com", current_password: "SecureP@ssw0rd123!" }
          }
          expect(response).to redirect_to(edit_settings_profile_path)
        end

        it "also updates name if included" do
          patch settings_profile_path, params: {
            user: { first_name: "New", email_address: "new@example.com", current_password: "SecureP@ssw0rd123!" }
          }
          expect(user.reload.first_name).to eq("New")
          expect(user.pending_email).to eq("new@example.com")
        end
      end

      context "without a fresh re-authentication (SEC-2b)" do
        it "redirects an email change to the reauthentication interstitial and starts no change" do
          user.sessions.update_all(reauthenticated_at: 1.hour.ago)
          patch settings_profile_path, params: { user: { email_address: "new@example.com" } }
          expect(response).to redirect_to(new_settings_reauthentication_path)
          expect(user.reload.pending_email).to be_nil
        end
      end

      context "passwordless user (SEC-2b: no password required)" do
        let(:user) { create(:user) } # passwordless; sign_in makes the session reauth-fresh

        it "allows an email change" do
          patch settings_profile_path, params: { user: { email_address: "new@example.com" } }
          expect(user.reload.pending_email).to eq("new@example.com")
        end
      end

      context "email change with same email" do
        it "ignores email change, updates other fields" do
          patch settings_profile_path, params: {
            user: { first_name: "Updated", email_address: user.email_address }
          }
          expect(user.reload.first_name).to eq("Updated")
          expect(user.pending_email).to be_nil
          expect(response).to redirect_to(edit_settings_profile_path)
        end
      end

      context "same email typed in the Unicode form of its stored punycode domain" do
        let(:user) { create(:user, email_address: "user@bücher.de") }

        it "is not an email change, so it needs no re-authentication" do
          user.sessions.update_all(reauthenticated_at: 1.hour.ago)
          patch settings_profile_path, params: {
            user: { first_name: "Updated", email_address: "user@bücher.de" }
          }
          expect(user.reload.first_name).to eq("Updated")
          expect(user.pending_email).to be_nil
          expect(response).to redirect_to(edit_settings_profile_path)
        end
      end

      context "passwordless user" do
        let(:user) { create(:user, password: nil, password_digest: nil) }

        it "updates name without email change" do
          patch settings_profile_path, params: {
            user: { first_name: "Updated" }
          }
          expect(user.reload.first_name).to eq("Updated")
        end
      end

      context "invalid params" do
        it "returns unprocessable entity for blank first_name" do
          patch settings_profile_path, params: { user: { first_name: "" } }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end
  end
end
