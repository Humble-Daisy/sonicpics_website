require "rails_helper"

RSpec.describe "User menu", type: :request do
  describe "authenticated user" do
    let(:user) { create(:user, first_name: "Jane", last_name: "Doe") }
    before { sign_in(user) }

    it "renders the user menu trigger with avatar initials" do
      get root_path
      expect(response.body).to include("JD")
      expect(response.body).to include('aria-haspopup="menu"')
    end

    it "includes a profile link in the user menu" do
      get root_path
      expect(response.body).to include(edit_settings_profile_path)
    end

    it "includes a sign out form in the user menu" do
      get root_path
      expect(response.body).to include('action="/session"')
    end

    it "displays user name and email in the menu" do
      get root_path
      expect(response.body).to include(CGI.escapeHTML(user.full_name))
      expect(response.body).to include(CGI.escapeHTML(user.email_address))
    end

    it "does not render inline sign-out link in desktop nav" do
      get root_path
      doc = Nokogiri::HTML(response.body)
      desktop_nav = doc.at_css(".hidden.md\\:flex")
      sign_out_buttons = desktop_nav.css('input[value="' + I18n.t("navigation.sign_out") + '"]')
      expect(sign_out_buttons.length).to eq(0)
    end
  end

  describe "unauthenticated user" do
    it "shows sign in link instead of user menu" do
      get new_session_path
      expect(response.body).to include(I18n.t("navigation.sign_in"))
      expect(response.body).not_to include('id="user-menu"')
    end
  end

  describe "Notifications menuitem (v2 — inside the user menu, between identity and All workspaces)" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    it "renders a Notifications link inside the desktop user menu wrapped in notifications_menu_count_frame" do
      get root_path
      doc = Nokogiri::HTML(response.body)
      desktop_menu = doc.at_css('#user-menu')
      expect(desktop_menu).not_to be_nil

      frame = desktop_menu.at_css('turbo-frame#notifications_menu_count_frame')
      expect(frame).not_to be_nil, "Notifications row must be wrapped in notifications_menu_count_frame so broadcasts can swap just the count"

      link = frame.at_css("a[href='#{settings_notifications_path}']")
      expect(link).not_to be_nil
      expect(link["role"]).to eq("menuitem")
      expect(link.text).to include(I18n.t("navigation.notifications"))
    end

    it "positions the Notifications row between the identity block and All workspaces" do
      get root_path
      doc = Nokogiri::HTML(response.body)
      menu = doc.at_css('#user-menu')

      # Direct anchor children of the menu container, in DOM order. Forms
      # (sign_out button_to) and turbo-frame elements get unwrapped to the
      # link/button inside for ordering purposes.
      hrefs = menu.css("a[role='menuitem'], form").map do |el|
        el.name == "form" ? el["action"] : el["href"]
      end

      profile_idx       = hrefs.index(edit_settings_profile_path)
      notifications_idx = hrefs.index(settings_notifications_path)
      workspaces_idx    = hrefs.index(workspaces_path)

      expect(profile_idx).not_to be_nil
      expect(notifications_idx).not_to be_nil
      expect(workspaces_idx).not_to be_nil
      expect(notifications_idx).to be > profile_idx
      expect(notifications_idx).to be < workspaces_idx
    end

    it "renders an aria-live count badge inside the Notifications row when unread is present" do
      PasswordChangedNotifier.with(record: user).deliver(user)
      get root_path
      doc = Nokogiri::HTML(response.body)
      frame = doc.at_css('turbo-frame#notifications_menu_count_frame')
      badge = frame.at_css("[aria-live='polite']")
      expect(badge).not_to be_nil, "count badge must carry aria-live so AT announces updates without re-rendering the whole menu"
      expect(badge.text.strip).to match(/\bnew\b/i)
      expect(badge["aria-label"]).to match(/unread notification/i)
    end

    it "omits the count badge when there are no unread notifications" do
      # sign_in fires SignInFromNewDeviceNotifier; clear so this case is truly empty.
      user.notifications.destroy_all
      get root_path
      doc = Nokogiri::HTML(response.body)
      frame = doc.at_css('turbo-frame#notifications_menu_count_frame')
      expect(frame.at_css("[aria-live='polite']")).to be_nil
    end

    it "renders the Notifications row inside the mobile menu panel" do
      get root_path
      doc = Nokogiri::HTML(response.body)
      mobile_panel = doc.at_css('#mobile-menu-panel')
      expect(mobile_panel).not_to be_nil

      mobile_notifications_link = mobile_panel.at_css("a[href='#{settings_notifications_path}']")
      expect(mobile_notifications_link).not_to be_nil
      expect(mobile_notifications_link.text).to include(I18n.t("navigation.notifications"))
    end
  end
end
