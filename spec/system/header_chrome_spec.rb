# frozen_string_literal: true

require "rails_helper"

# The header paints from the chrome tokens, so a fork rebrands it from _brand.css alone.
RSpec.describe "Header chrome", type: :system do
  let(:user) { create(:user) }

  before { sign_in_via_form(user) }

  def computed(selector, property)
    page.evaluate_script(
      "getComputedStyle(document.querySelector(#{selector.to_json}))[#{property.to_json}]"
    )
  end

  # A token resolved through a probe element, so it compares as the same rgb() string.
  def resolved(token)
    page.evaluate_script(<<~JS)
      (function() {
        var probe = document.createElement("div");
        probe.style.color = "var(#{token})";
        document.body.appendChild(probe);
        var value = getComputedStyle(probe).color;
        probe.remove();
        return value;
      })()
    JS
  end

  def brand_the_chrome
    page.execute_script(<<~JS)
      var root = document.documentElement.style;
      root.setProperty("--color-chrome", "oklch(27.1% 0.080 251.6)");
      root.setProperty("--color-chrome-border", "oklch(86.3% 0.176 89.8)");
      root.setProperty("--chrome-border-width", "4px");
      root.setProperty("--color-on-chrome", "oklch(100% 0 0)");
      root.setProperty("--color-on-chrome-strong", "oklch(100% 0 0)");
      root.setProperty("--color-on-chrome-muted", "oklch(86.9% 0.020 252.9)");
      root.setProperty("--color-on-chrome-hover", "oklch(86.3% 0.176 89.8)");
      root.setProperty("--color-chrome-mark", "oklch(86.3% 0.176 89.8)");
      root.setProperty("--color-chrome-focus", "oklch(86.3% 0.176 89.8)");
    JS
  end

  # Puts the family back on its defaults, so the example holds in a fork whose _brand.css sets it.
  def unbrand_the_chrome
    page.execute_script(<<~JS)
      var root = document.documentElement.style;
      root.setProperty("--color-chrome", "var(--color-surface-raised)");
      root.setProperty("--color-chrome-border", "var(--color-border)");
      root.setProperty("--chrome-border-width", "1px");
      root.setProperty("--color-on-chrome", "var(--color-text-body)");
      root.setProperty("--color-on-chrome-strong", "var(--color-text-heading)");
      root.setProperty("--color-chrome-mark", "var(--color-text-heading)");
    JS
  end

  def toggle = "header button[data-theme-toggle-target='button']"
  def wordmark = "header a[href='#{root_path}'] span"

  it "lets a brand stylesheet that loads before the app's set the chrome" do
    visit root_path
    page.execute_script(<<~JS)
      var brand = document.createElement("style");
      brand.textContent = ":root { --color-chrome: oklch(35% 0.12 150); " +
        "--color-on-chrome: oklch(100% 0 0); --color-on-chrome-strong: oklch(100% 0 0); " +
        "--color-on-chrome-muted: oklch(100% 0 0); --color-on-chrome-hover: oklch(100% 0 0); " +
        "--color-chrome-mark: oklch(100% 0 0); --color-chrome-focus: oklch(100% 0 0); }";
      document.head.prepend(brand);
    JS

    # Either this rule or a fork's own _brand.css may win; the defaults must not.
    expect(resolved("--color-chrome")).not_to eq(resolved("--color-surface-raised")),
      "a :root brand rule loaded ahead of the app's stylesheet lost to the chrome defaults"
    expect(computed("header", "backgroundColor")).to eq(resolved("--color-chrome"))
  end

  it "keeps today's header with the chrome family at its defaults" do
    visit root_path
    unbrand_the_chrome

    expect(computed("header", "backgroundColor")).to eq(resolved("--color-surface-raised"))
    expect(computed("header", "borderBottomColor")).to eq(resolved("--color-border"))
    expect(computed("header", "borderBottomWidth")).to eq("1px")
    expect(computed(wordmark, "color")).to eq(resolved("--color-text-heading"))
    expect(computed(toggle, "color")).to eq(resolved("--color-text-body"))
  end

  it "paints the bar from the chrome tokens once a brand sets them" do
    visit root_path
    brand_the_chrome

    expect(computed("header", "backgroundColor")).to eq(resolved("--color-chrome"))
    expect(computed("header", "borderBottomColor")).to eq(resolved("--color-chrome-border"))
    expect(computed("header", "borderBottomWidth")).to eq("4px")
    expect(computed(wordmark, "color")).to eq(resolved("--color-on-chrome-strong"))
    expect(computed("header a[href='#{root_path}'] svg", "color")).to eq(resolved("--color-chrome-mark"))
    expect(computed(toggle, "color")).to eq(resolved("--color-on-chrome"))
  end

  it "leaves the account menu on its own surface under a branded bar" do
    visit root_path
    brand_the_chrome
    find("#user-menu-button").click

    expect(page).to have_css("#user-menu", visible: true)
    expect(computed("#user-menu", "backgroundColor")).to eq(resolved("--color-surface-raised"))
    expect(computed("#user-menu [role='menuitem']", "color")).not_to eq(resolved("--color-on-chrome"))
  end

  it "rings the bar's controls in the chrome focus color" do
    visit root_path
    brand_the_chrome
    cdp_execute("document.activeElement && document.activeElement.blur()")
    reached = (1..15).any? do
      cdp_press("Tab")
      cdp_evaluate("document.activeElement === document.querySelector(#{toggle.to_json})")
    end
    raise "could not reach the theme toggle via Tab" unless reached

    expect(computed(toggle, "outlineColor")).to eq(resolved("--color-chrome-focus"))
  end

  it "keeps the mobile menu panel on its own surface under a branded bar" do
    page.current_window.resize_to(390, 900)
    visit root_path
    brand_the_chrome
    find("header button[aria-controls='mobile-menu-panel']").click

    expect(page).to have_css("#mobile-menu-panel", visible: true)
    expect(computed("#mobile-menu-panel", "backgroundColor")).to eq(resolved("--color-surface-raised"))
  end

  it "stays AAA in both themes once a brand sets the chrome" do
    visit root_path
    brand_the_chrome

    expect_aaa_in_both_themes(include: "header")
  end

  it "keeps the signed-out bar AAA once a brand sets the chrome" do
    Capybara.reset_session!
    visit new_session_path
    brand_the_chrome

    expect(page).to have_link(I18n.t("navigation.sign_in"), href: new_session_path)
    expect_aaa_in_both_themes(include: "header")
  end
end
