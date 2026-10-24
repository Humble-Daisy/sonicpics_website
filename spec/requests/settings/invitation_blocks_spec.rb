require "rails_helper"

# Self-serve undo for a block, keyed on the signed-in user's own address (#812).
RSpec.describe "Settings::InvitationBlocks", type: :request do
  let(:user) { create(:user) }
  let(:inviter) { create(:user, first_name: "Dana", last_name: "Sender") }

  describe "unauthenticated access" do
    it "redirects GET /account/invitation_blocks to sign in" do
      get settings_invitation_blocks_path
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects DELETE /account/invitation_blocks/:id to sign in" do
      delete settings_invitation_block_path(create(:invitation_block))
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET index" do
    before { sign_in(user) }

    it "lists the blocks naming the signed-in user's address" do
      create(:invitation_block, inviter: inviter, email: user.email_address)

      get settings_invitation_blocks_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dana Sender")
    end

    it "names each Allow again button with the words it shows (WCAG 2.5.3 Label in Name)" do
      create(:invitation_block, inviter: inviter, email: user.email_address)

      get settings_invitation_blocks_path

      button = Capybara.string(response.body).find("button[data-action='click->modal#open']")
      expect(button[:"aria-label"]).to contain_visible_text(button.text).and include("Dana Sender")
    end

    it "does not list a block against somebody else's address" do
      create(:invitation_block, inviter: inviter, email: "someone-else@example.com")

      get settings_invitation_blocks_path

      expect(response.body).not_to include("Dana Sender")
    end

    it "renders an empty state when the user has blocked nobody" do
      get settings_invitation_blocks_path

      expect(response).to have_http_status(:ok)
      # As text: the copy's apostrophe and curly quotes reach the body escaped.
      expect(Nokogiri::HTML(response.body).text)
        .to include(I18n.t("settings.invitation_blocks.index.empty_state"))
    end
  end

  describe "DELETE destroy" do
    before { sign_in(user) }

    it "removes the block and restores delivery from that sender" do
      workspace = create(:workspace)
      invitation = create(:invitation, email: user.email_address, invitable: workspace, invited_by: inviter)
      InvitationBlock.block!(inviter: inviter, email: user.email_address)
      block = InvitationBlock.find_by!(inviter: inviter, email: user.email_address)
      expect(invitation.reload.suppressed_at).to be_present

      delete settings_invitation_block_path(block)

      expect(response).to redirect_to(settings_invitation_blocks_path)
      expect(InvitationBlock.exists?(block.id)).to be(false)
      # The stamp is cleared too, or bulk_invite! mints duplicates.
      expect(invitation.reload.suppressed_at).to be_nil
    end

    # A foreign id gets the same not-found alert as a missing one: asserting the ALERT
    # proves the requester cannot tell a real block from none (#812).
    it "answers a block belonging to another address as not-found, not forbidden" do
      block = create(:invitation_block, inviter: inviter, email: "not-mine@example.com")

      delete settings_invitation_block_path(block)

      expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
      expect(InvitationBlock.exists?(block.id)).to be(true)
    end
  end
end
