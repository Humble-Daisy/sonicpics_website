require "rails_helper"

RSpec.describe "Accessibility simulation drop-up", type: :system do
  def trigger_button
    find("button[data-a11y-sim-target='trigger']")
  end

  def mode_item(mode_key)
    find("button[role='menuitemradio']", text: I18n.t("a11y_sim.modes.#{mode_key}"))
  end

  def press_key(key)
    cdp_press(key)
  end

  describe "outside development" do
    it "does not render the trigger" do
      visit root_path
      expect(page).to have_css("h1", text: I18n.t("pages.home.hero.title"))
      expect(page).not_to have_content(I18n.t("a11y_sim.dev_badge"))
    end
  end

  describe "in development" do
    before { allow(Rails.env).to receive(:development?).and_return(true) }

    it "renders the trigger in the footer with the Normal mode label" do
      visit root_path
      within("footer") do
        expect(page).to have_content(I18n.t("a11y_sim.dev_badge"))
        expect(page).to have_content(I18n.t("a11y_sim.prefix"))
        expect(page).to have_content(I18n.t("a11y_sim.modes.normal"))
      end
    end

    it "is named by the words it shows, so the name follows the mode (WCAG 2.5.3 Label in Name)" do
      visit root_path
      expect(trigger_button[:"aria-label"]).to be_nil
      expect(trigger_button).to have_no_css("[aria-hidden='true']", text: I18n.t("a11y_sim.dev_badge"))
    end

    it "opens the menu when the trigger is clicked" do
      visit root_path
      dismiss_cookie_banner
      trigger_button.click
      expect(page).to have_css("[role='menu']:not(.hidden)")
      I18n.t("a11y_sim.modes").each_value do |label|
        expect(page).to have_content(label)
      end
    end

    it "applies the matching body class when a mode is selected" do
      visit root_path
      dismiss_cookie_banner
      trigger_button.click
      mode_item(:blur).click

      expect(page).to have_css("body.a11y-sim-blur")
      expect(page).not_to have_css("body.a11y-sim-deuteranopia")
    end

    # Color-vision-deficiency variants: each needs its SVG color-matrix <filter> in
    # the DOM (so the CSS `filter: url(#...)` resolves) AND applies its body class.
    %i[protanopia tritanopia achromatopsia].each do |cvd|
      it "provides the #{cvd} color-vision filter (SVG matrix def + body class)" do
        visit root_path
        dismiss_cookie_banner
        expect(page).to have_css("filter#a11y-sim-#{cvd}", visible: :all)
        trigger_button.click
        mode_item(cvd).click
        expect(page).to have_css("body.a11y-sim-#{cvd}")
      end
    end

    it "reveals a description tooltip on hover, wired via aria-describedby" do
      visit root_path
      dismiss_cookie_banner
      trigger_button.click
      item = mode_item(:protanopia)
      item.hover
      expect(page).to have_css("[role='tooltip']", text: I18n.t("a11y_sim.descriptions.protanopia"), visible: true)
      expect(item["aria-describedby"]).to be_present
    end

    it "closes the menu and clears the body class when returning to Normal" do
      visit root_path
      dismiss_cookie_banner
      trigger_button.click
      mode_item(:deuteranopia).click
      expect(page).to have_css("body.a11y-sim-deuteranopia")

      trigger_button.click
      mode_item(:normal).click
      expect(page).not_to have_css("body.a11y-sim-deuteranopia")
      expect(page).not_to have_css("body[class*='a11y-sim-']")
    end

    it "announces the selected mode to screen readers via an aria-live region" do
      visit root_path
      dismiss_cookie_banner
      trigger_button.click
      mode_item(:grayscale).click

      expected = I18n.t("a11y_sim.announcement_template", mode: I18n.t("a11y_sim.modes.grayscale"))
      expect(page).to have_css("[role='status'][aria-live='polite']", text: expected, visible: :all)
    end

    it "toggles the menu via the Ctrl/Cmd+Shift+A keyboard shortcut" do
      visit root_path
      dismiss_cookie_banner
      expect(page).to have_css("[role='menu'].hidden", visible: :all)

      # Controller accepts either metaKey or ctrlKey; Control works cross-platform in Playwright.
      press_key("Control+Shift+KeyA")

      expect(page).to have_css("[role='menu']:not(.hidden)")
    end

    it "falls back to Normal when asked to apply an invalid mode" do
      visit root_path
      dismiss_cookie_banner
      # Simulate a corrupted localStorage value, then ask the controller to re-apply.
      page.execute_script(<<~JS)
        window.localStorage.setItem('a11y_sim_mode', 'not-a-real-mode');
      JS
      page.refresh
      expect(page).to have_css("button[data-a11y-sim-target='trigger']")
      expect(page).not_to have_css("body[class*='a11y-sim-']")
    end

    it "still applies filters when localStorage.setItem throws" do
      visit root_path
      dismiss_cookie_banner
      # Override setItem to throw, simulating Safari private-browsing quota error.
      page.execute_script(<<~JS)
        const proto = Object.getPrototypeOf(window.localStorage);
        Object.defineProperty(proto, 'setItem', {
          value: () => { throw new Error('QuotaExceededError'); },
          configurable: true
        });
      JS
      trigger_button.click
      mode_item(:blur).click
      expect(page).to have_css("body.a11y-sim-blur")
    end

    describe "keyboard navigation" do
      it "moves focus to the next item on ArrowDown" do
        visit root_path
        dismiss_cookie_banner
        trigger_button.click
        press_key("ArrowDown")
        expect(page.evaluate_script("document.activeElement.dataset.mode")).to eq("blur")
      end

      it "wraps focus to the last item when ArrowUp is pressed from the first item" do
        visit root_path
        dismiss_cookie_banner
        trigger_button.click
        press_key("ArrowUp")
        expect(page.evaluate_script("document.activeElement.dataset.mode")).to eq("cataract")
      end

      it "jumps focus to the last item on End and first item on Home" do
        visit root_path
        dismiss_cookie_banner
        trigger_button.click
        press_key("End")
        expect(page.evaluate_script("document.activeElement.dataset.mode")).to eq("cataract")
        press_key("Home")
        expect(page.evaluate_script("document.activeElement.dataset.mode")).to eq("normal")
      end

      it "closes the menu when Tab is pressed" do
        visit root_path
        dismiss_cookie_banner
        trigger_button.click
        expect(page).to have_css("[role='menu']:not(.hidden)")
        press_key("Tab")
        expect(page).not_to have_css("[role='menu']:not(.hidden)")
      end
    end
  end
end
