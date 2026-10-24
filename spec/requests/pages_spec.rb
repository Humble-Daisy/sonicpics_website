require "rails_helper"

# One pages resource, show keyed by name; the templates are the allowlist (#1007).
RSpec.describe "Pages", type: :request do
  describe "GET /" do
    it "returns the home page" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.home.hero.title"))
    end

    it "offers the App Store download in place of a sign-up CTA" do
      get root_path
      expect(Capybara.string(response.body)).to have_link(
        I18n.t("pages.home.hero.cta_primary"), href: I18n.t("pages.home.app_store_url")
      )
    end
  end

  # The public site is a brochure, like the original sonicpics.com: the logo is
  # the home link, Contact and Support are the only other links, and no page
  # leads into accounts.
  describe "brochure chrome" do
    PagesController::PAGES.each do |name|
      it "frames the #{name} page with the logo, Contact and Support, and no account links" do
        get(name == "home" ? root_path : page_path(name))
        header = Capybara.string(response.body).find("header")

        expect(header).to have_link(href: root_path) { |link| link.has_css?("img[alt='#{I18n.t("pages.chrome.home")}']") }
        expect(header).to have_link(I18n.t("pages.chrome.contact"), href: page_path(:contact))
        expect(header).to have_link(I18n.t("pages.chrome.support"), href: page_path(:support))
        expect(response.body).not_to include(new_session_path)
      end
    end

    it "marks the current page in the header" do
      get page_path(:support)
      header = Capybara.string(response.body).find("header")
      expect(header).to have_css("a[aria-current='page']", text: I18n.t("pages.chrome.support"))
      expect(header).to have_no_css("a[aria-current]", text: I18n.t("pages.chrome.contact"))
    end

    it "credits Humble Daisy in the footer" do
      get root_path
      expect(Capybara.string(response.body).find("footer")).to have_link(href: I18n.t("pages.chrome.company_url"))
    end

    it "gives a signed-in user the app chrome, so the app stays reachable" do
      sign_in(create(:user))
      get root_path
      expect(Capybara.string(response.body)).to have_css("#user-menu-button")
    end
  end

  describe "GET /about" do
    it "returns the about page with mission" do
      get page_path(:about)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.about.hero.title"))
    end
  end

  describe "GET /privacy" do
    it "returns the privacy page with policy sections" do
      get page_path(:privacy)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.privacy.title"))
    end

    # A literal: a redefined date.formats.long changes this string.
    it "renders the policy date in the :long format" do
      get page_path(:privacy)
      expect(response.body).to include("July 06, 2015")
    end
  end

  describe "GET /contact" do
    it "returns the contact page with methods" do
      get page_path(:contact)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.contact.hero.title"))
    end
  end

  describe "GET /support" do
    it "returns the support page" do
      get page_path(:support)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.support.title"))
    end
  end

  describe "GET /sample_uses" do
    it "returns the sample uses page" do
      get page_path(:sample_uses)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.sample_uses.title"))
    end
  end

  describe "GET /:id for a name that is not a page" do
    it "is not routable, so the constraint is the first fence" do
      get "/pricing"
      expect(response).to have_http_status(:not_found)
    end
  end
end
