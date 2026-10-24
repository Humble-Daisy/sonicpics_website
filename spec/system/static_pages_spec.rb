require "rails_helper"

RSpec.describe "Static pages", type: :system do
  describe "layout" do
    it "has a skip-to-content link" do
      visit root_path
      expect(page).to have_css("a[href='#main-content']", visible: :all)
    end

    it "has a main content landmark" do
      visit root_path
      expect(page).to have_css("main#main-content")
    end

    it "has a lang attribute on html" do
      visit root_path
      expect(page).to have_css("html[lang='en']")
    end

    it "has the theme controller on the html element" do
      visit root_path
      expect(page).to have_css("html[data-controller~='theme']")
    end

    it "has a header with navigation" do
      visit root_path
      expect(page).to have_css("header nav")
    end

    it "displays the site logo SVG in the header" do
      visit new_session_path
      within("header nav") do
        expect(page).to have_css("svg[aria-hidden='true']")
      end
    end

    it "has a footer" do
      visit root_path
      expect(page).to have_css("footer")
    end

    it "footer contains site links" do
      visit new_session_path
      within("footer") do
        expect(page).to have_link(I18n.t("footer.about"))
        expect(page).to have_link(I18n.t("footer.privacy"))
        expect(page).to have_link(I18n.t("footer.contact"))
      end
    end

    it "displays the site logo in the footer" do
      visit new_session_path
      within("footer") do
        expect(page).to have_css("svg[aria-hidden='true']")
        expect(page).to have_text(I18n.t("application.name"))
      end
    end

    it "navigation contains the app name as home link" do
      visit root_path
      within("header nav") do
        expect(page).to have_link(I18n.t("application.name"), href: root_path)
      end
    end

    it "has a theme toggle button" do
      visit new_session_path
      within("header nav") do
        expect(page).to have_css("button[aria-label]", text: /Light|Dark|System/i, visible: :all)
      end
    end

    it "has a mobile menu toggle button" do
      visit new_session_path
      expect(page).to have_button(I18n.t("navigation.mobile_menu.open"), visible: :all)
    end

    it "has toast containers for pills and cards" do
      visit root_path
      expect(page).to have_css("#toast-pills[aria-label]", visible: :all)
      expect(page).to have_css("#toast-cards[aria-label]", visible: :all)
    end
  end

  describe "toast notifications" do
    let(:user) { create(:user) }

    it "shows a pill toast with progress bar on successful sign-in" do
      sign_in_via_form(user)
      expect(page).to have_css("[data-controller='toast-pill']")
      expect(page).to have_css("[data-toast-pill-target='progress']")
    end
  end

  # Records readyState when `dark` first appears: "loading" means the inline script
  # painted it before first paint, anything later means a flash (#624).
  describe "theme before first paint" do
    def recording_when_dark_first_appears
      cdp = page.driver.browser.page
      recorder = cdp.command("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
        new MutationObserver(function () {
          var el = document.documentElement;
          if (el && el.classList.contains("dark") && !window.__darkAppliedAt) {
            window.__darkAppliedAt = document.readyState;
          }
        }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: [ "class" ] });
      JS
      yield
    ensure
      cdp&.command("Page.removeScriptToEvaluateOnNewDocument", identifier: recorder["identifier"]) if recorder
    end

    def dark_first_appeared_at
      page.evaluate_script("window.__darkAppliedAt")
    end

    def with_os_preferring(scheme)
      cdp = page.driver.browser.page
      cdp.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: scheme } ])
      yield
    ensure
      cdp.command("Emulation.setEmulatedMedia", features: [])
    end

    def choose_theme(*cycle_stops)
      visit new_session_path
      cycle_stops.each { find("[data-controller='theme-toggle']").click }
    end

    it "paints a dark preference before the modules run, across a fresh page load" do
      choose_theme(:light, :dark)
      expect(page).to have_css("html.dark")

      recording_when_dark_first_appears do
        visit new_session_path
        expect(page).to have_css("html[data-theme-theme-value='dark']")
        expect(page).to have_css("html.dark")
        expect(dark_first_appeared_at).to eq("loading")
      end
    end

    it "leaves a light preference free of any dark flash" do
      choose_theme(:light)
      expect(page).to have_css("html[data-theme-theme-value='light']")

      recording_when_dark_first_appears do
        visit new_session_path
        expect(page).to have_css("html[data-theme-theme-value='light']")
        expect(page).to have_no_css("html.dark")
        expect(dark_first_appeared_at).to be_nil
      end
    end

    it "paints dark before the modules run when the preference is system and the OS prefers dark" do
      with_os_preferring("dark") do
        recording_when_dark_first_appears do
          visit new_session_path
          expect(page).to have_css("html.dark")
          expect(dark_first_appeared_at).to eq("loading")
        end
      end
    end
  end

  describe "home page" do
    before { visit root_path }

    it "displays the hero title" do
      expect(page).to have_text(I18n.t("pages.home.hero.title"))
    end

    it "displays the hero subtitle" do
      expect(page).to have_text(I18n.t("pages.home.hero.subtitle"))
    end

    it "links to the App Store rather than to sign-up, even when signups are open" do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
      visit root_path
      expect(page).to have_link(I18n.t("pages.home.hero.cta_primary"))
      expect(page).to have_no_link(I18n.t("navigation.sign_up"))
    end

    it "displays feature cards" do
      expect(page).to have_text(I18n.t("pages.home.features.slideshows.title"))
      expect(page).to have_text(I18n.t("pages.home.features.narration.title"))
      expect(page).to have_text(I18n.t("pages.home.features.sharing.title"))
    end
  end

  describe "about page" do
    before { visit page_path(:about) }

    it "displays the page title" do
      expect(page).to have_text(I18n.t("pages.about.hero.title"))
    end

    it "displays the mission" do
      expect(page).to have_text(I18n.t("pages.about.mission.title"))
    end

    it "lists key features" do
      expect(page).to have_text(I18n.t("pages.about.features.title"))
    end
  end

  describe "privacy page" do
    before { visit page_path(:privacy) }

    it "displays the page title" do
      expect(page).to have_text(I18n.t("pages.privacy.title"))
    end

    it "has policy sections" do
      expect(page).to have_text(I18n.t("pages.privacy.collection.title"))
      expect(page).to have_text(I18n.t("pages.privacy.usage.title"))
      expect(page).to have_text(I18n.t("pages.privacy.security.title"))
    end
  end

  describe "contact page" do
    before { visit page_path(:contact) }

    it "displays the page title" do
      expect(page).to have_text(I18n.t("pages.contact.hero.title"))
    end

    it "displays contact methods" do
      expect(page).to have_text(I18n.t("pages.contact.methods.title"))
    end
  end

  %w[about privacy contact support sample_uses].each do |page_name|
    describe "#{page_name} page" do
      it "renders with 200 status" do
        visit page_path(page_name)
        expect(page).to have_text(I18n.t("pages.#{page_name}.title", default: I18n.t("pages.#{page_name}.hero.title", default: page_name.titleize)))
      end
    end
  end

  describe "accessibility (axe-core)" do
    # Audits at WCAG 2.2 AAA — the project standard. `axe_clean_in_both_themes?`
    # toggles to light, runs axe; toggles to dark, runs axe; ANDs the result.
    let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

    %w[home about privacy contact support sample_uses].each do |page_name|
      it "#{page_name} page passes automated accessibility checks (light + dark)" do
        path = page_name == "home" ? root_path : page_path(page_name)
        visit path
        expect(axe_clean_in_both_themes?(axe_options)).to be(true),
          "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
      end
    end

    it "sign-in page passes automated accessibility checks (light + dark)" do
      visit new_session_path
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end

    # sessions/new is the single entry point for both sign-in and sign-up
    # (passwordless-first posture). The sign-in accessibility test above already
    # covers this page; this example is retained as a named anchor for the
    # sign-up entry path now that registration/new is removed.
    it "sign-up entry page (sessions/new) passes automated accessibility checks (light + dark)" do
      visit new_session_path
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end
end
