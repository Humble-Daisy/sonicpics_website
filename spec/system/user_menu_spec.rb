require "rails_helper"

# D1 simplified the user-menu dropdown to a clickable identity-block row
# (avatar + name + email linking to the personal-context profile) and a
# sign-out button. Notifications + Notification preferences moved out of
# the dropdown (notifications live on the standalone header bell;
# preferences live in the Settings hub sidebar).
#
# Post-D1 addition: an "All workspaces" link (workspaces#index) was added
# between identity and sign-out so signed-in users on non-workspace-scoped
# pages (marketing landing, auth flows) have an in-product path to their
# workspaces list. The header workspace switcher (Phase 2b) only renders on
# workspace-scoped pages — the workspaces index is outside that scope.
RSpec.describe "User menu dropdown", type: :system do
  let(:user) { create(:user, first_name: "Jane", last_name: "Doe") }

  # Invoke a keyboard event on the menu controller directly. Programmatic
  # KeyboardEvent dispatch does not reliably reach Stimulus listeners through
  # the driver's isolated evaluation context, so we call the handler directly.
  def send_dropdown_key(key)
    cdp_execute(<<~JS)
      (function() {
        var el = document.querySelector('[data-controller~="menu"]');
        var c = window.Stimulus.getControllerForElementAndIdentifier(el, 'menu');
        if (c) c.navigate(new KeyboardEvent('keydown', { key: '#{key}', bubbles: true }));
      })()
    JS
  end

  before do
    sign_in_via_form(user)
    visit root_path # this file's old helper copy baked this in; the examples assume it
  end

  # #685: the user menu runs on the menu-pattern controller (APG menu-button),
  # not the legacy dropdown — type-ahead works and outside-click dismissal
  # leaves focus where the user clicked instead of yanking it to the trigger
  # (WCAG 3.2.1/2.4.3).
  describe "menu-pattern behaviors (#685)" do
    def send_menu_key(key)
      cdp_execute(<<~JS)
        (function() {
          var el = document.querySelector('[data-controller~="menu"]');
          var c = window.Stimulus.getControllerForElementAndIdentifier(el, 'menu');
          if (c) c.navigate(new KeyboardEvent('keydown', { key: '#{key}', bubbles: true }));
        })()
      JS
    end

    it "type-ahead focuses the item matching typed characters" do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)

      send_menu_key("s")

      focused = page.evaluate_script("document.activeElement.textContent.trim()")
      expect(focused).to eq(I18n.t("navigation.sign_out"))
    end

    it "outside click closes without stealing focus back to the trigger" do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)

      find("h1", match: :first).click
      expect(page).to have_no_css("#user-menu", visible: :visible)

      expect(page.evaluate_script("document.activeElement.id")).not_to eq("user-menu-button")
    end
  end

  describe "opening and closing" do
    it "opens on click and shows menu items" do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)
      expect(page).to have_text(user.full_name)
      expect(page).to have_text(user.email_address)
    end

    it "closes on second click" do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)
      find("#user-menu-button").click
      expect(page).to have_no_css("#user-menu", visible: :visible)
    end

    it "closes on Escape key" do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)
      send_dropdown_key("Escape")
      expect(page).to have_no_css("#user-menu", visible: :visible)
    end
  end

  describe "dropdown contents (identity block + all workspaces + sign out)" do
    before do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)
    end

    it "renders a clickable identity block linking to the personal-context profile" do
      within "#user-menu" do
        expect(page).to have_link(href: edit_settings_profile_path)
        # Identity block carries the user's full name + email address
        expect(page).to have_text(user.full_name)
        expect(page).to have_text(user.email_address)
      end
    end

    it "renders an All workspaces link to the workspaces index" do
      within "#user-menu" do
        expect(page).to have_link(I18n.t("navigation.all_workspaces"), href: workspaces_path)
      end
    end

    it "renders a sign-out button" do
      within "#user-menu" do
        expect(page).to have_button(I18n.t("navigation.sign_out"))
      end
    end

    it "does NOT render a separate Profile link (the identity block IS the profile link)" do
      within "#user-menu" do
        # The dropdown still routes to the profile page via the identity
        # block — there should not be a SECOND text link labeled "Profile".
        expect(page).not_to have_link(I18n.t("navigation.profile"))
      end
    end

    it "renders a Notifications link (v2: standalone bell removed; user menu is the canonical triage entry)" do
      within "#user-menu" do
        expect(page).to have_link(I18n.t("navigation.notifications"), href: settings_notifications_path)
      end
    end

    it "does NOT render a Notification preferences link (accessible via Settings sidebar)" do
      within "#user-menu" do
        expect(page).not_to have_link(I18n.t("navigation.notification_preferences"))
        expect(page).not_to have_link(href: edit_settings_notification_preferences_path)
      end
    end
  end

  describe "keyboard navigation" do
    before do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)
    end

    it "focuses first menu item (identity link) on open" do
      focused_href = page.evaluate_script("document.activeElement?.getAttribute('href')")
      expect(focused_href).to eq(edit_settings_profile_path)
    end

    it "ArrowDown moves focus from identity to Notifications (second item, v2)" do
      send_dropdown_key("ArrowDown")
      focused_href = page.evaluate_script("document.activeElement?.getAttribute('href')")
      expect(focused_href).to eq(settings_notifications_path)
    end

    it "ArrowDown twice moves focus to All workspaces (third item)" do
      send_dropdown_key("ArrowDown") # identity → Notifications
      send_dropdown_key("ArrowDown") # Notifications → All workspaces
      focused_href = page.evaluate_script("document.activeElement?.getAttribute('href')")
      expect(focused_href).to eq(workspaces_path)
    end

    it "ArrowDown thrice moves focus to sign-out (fourth and final item)" do
      send_dropdown_key("ArrowDown")
      send_dropdown_key("ArrowDown")
      send_dropdown_key("ArrowDown") # All workspaces → sign-out
      focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")
      expect(focused_text).to eq(I18n.t("navigation.sign_out"))
    end

    it "ArrowDown wraps from last to first item" do
      send_dropdown_key("ArrowDown") # identity → Notifications
      send_dropdown_key("ArrowDown") # Notifications → All workspaces
      send_dropdown_key("ArrowDown") # All workspaces → sign-out
      send_dropdown_key("ArrowDown") # sign-out → wraps to identity
      focused_href = page.evaluate_script("document.activeElement?.getAttribute('href')")
      expect(focused_href).to eq(edit_settings_profile_path)
    end

    it "ArrowUp wraps from first to last item" do
      send_dropdown_key("ArrowUp")
      focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")
      expect(focused_text).to eq(I18n.t("navigation.sign_out"))
    end

    it "Home key focuses first item" do
      send_dropdown_key("ArrowDown")
      send_dropdown_key("Home")
      focused_href = page.evaluate_script("document.activeElement?.getAttribute('href')")
      expect(focused_href).to eq(edit_settings_profile_path)
    end

    it "End key focuses last item" do
      send_dropdown_key("End")
      focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")
      expect(focused_text).to eq(I18n.t("navigation.sign_out"))
    end

    it "returns focus to trigger button on Escape" do
      send_dropdown_key("Escape")
      focused_id = page.evaluate_script("document.activeElement?.id")
      expect(focused_id).to eq("user-menu-button")
    end

    # The menu controller activates natively (real Enter/Space on the focused
    # <a>/<button> — no synthetic click), so these drive real key input.
    # Native semantics: Enter follows links; Space activates BUTTONS only.
    it "Enter key activates the focused identity link" do
      find("#user-menu a[href='#{edit_settings_profile_path}']").send_keys(:enter)
      expect(page).to have_current_path(edit_settings_profile_path)
    end

    it "Space key activates the focused sign-out button" do
      find("#user-menu button", text: I18n.t("navigation.sign_out")).send_keys(:space)
      expect(page).to have_current_path(new_session_path)
    end
  end

  describe "navigation" do
    it "identity-block link navigates to profile page" do
      find("#user-menu-button").click
      within "#user-menu" do
        find("a[href='#{edit_settings_profile_path}']").click
      end
      expect(page).to have_current_path(edit_settings_profile_path)
    end

    # Regression: the Notifications row lives inside
    # <turbo-frame id="notifications_menu_count_frame"> (so the broadcaster
    # can swap just the [N new] count). A bare link inside a frame navigates
    # THAT frame — the index response has no matching frame, so Turbo renders
    # "Content missing" in the dropdown instead of loading the page. The link
    # must break out to _top.
    it "Notifications link navigates to the full notifications index (breaks out of the count frame)" do
      find("#user-menu-button").click
      within "#user-menu" do
        find("a[href='#{settings_notifications_path}']").click
      end
      expect(page).to have_current_path(settings_notifications_path)
      expect(page).to have_css("h1", text: I18n.t("notifications.index.heading"))
      expect(page).to have_no_text("Content missing")
    end

    it "sign out ends session" do
      find("#user-menu-button").click
      click_button I18n.t("navigation.sign_out")
      expect(page).to have_current_path(new_session_path)
    end
  end

  # #713. Turbo's snapshot clone normalises only `select`, `input[type=password]`
  # and `noscript`, and `menu_controller#disconnect()` only cancels the type-ahead —
  # so a menu still open when the page is cached is frozen open. Back then restores a
  # `role="menu"` with live menuitems (this panel is `absolute`, so `topLayer.enable`
  # no-ops on it and there is no closed-popover `display: none` to hide it) under a
  # trigger that reports `aria-expanded="true"`, and the first click on that trigger
  # is dead — the controller thinks the menu is already open.
  describe "Turbo snapshot restore (#713)" do
    it "restores with the menu closed and the trigger reporting collapsed" do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)

      # A programmatic Turbo visit, not a click. Every click path closes the menu
      # first by design — an item runs `menu#activate`, anything else runs
      # `menu#closeOnClickOutside` — so a navigation that does not originate in a
      # click (a `turbo_stream` redirect action, or any `Turbo.visit`) is the
      # reachable way to cache a page with a menu still open. `visit` is not usable:
      # it is a hard browser goto, fires no `turbo:before-cache`, and leaves the
      # snapshot cache empty.
      page.execute_script("window.Turbo.visit('#{page_path(:about)}')")
      expect(page).to have_current_path(page_path(:about))

      page.go_back
      expect(page).to have_current_path(root_path)

      expect(page).to have_no_css("#user-menu", visible: :visible)
      expect(page).to have_css("#user-menu[hidden]", visible: :all)
      expect(page).to have_css("#user-menu-button[aria-expanded='false']")
      expect(page).to have_css("[data-controller~='menu'][data-menu-open-value='false']:has(#user-menu)",
        visible: :all)
    end
  end

  describe "unauthenticated" do
    it "shows sign in link instead of avatar" do
      Capybara.reset_sessions!
      visit new_session_path
      expect(page).to have_link(I18n.t("navigation.sign_in"))
      expect(page).to have_no_css("#user-menu-button", visible: :visible)
    end
  end
end
