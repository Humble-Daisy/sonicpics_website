require "rails_helper"

RSpec.describe "shared/_user_menu_avatar_button.html.erb", type: :view do
  let(:user) { create(:user, first_name: "Nell", last_name: "Ramirez") }

  it "renders a button with id #user-menu-button (stable test hook)" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to include('id="user-menu-button"')
    expect(rendered).to include('aria-haspopup="menu"')
    expect(rendered).to include('aria-expanded="false"')
    expect(rendered).to include('aria-controls="user-menu"')
  end

  it "names the button with the initials it shows, then the user (WCAG 2.5.3 Label in Name)" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to match(/aria-label="NR, open user menu for Nell Ramirez"/)
  end

  it "does NOT carry aria-labelledby pointing to a broadcast-replaceable frame (D1)" do
    # Pre-D1 the avatar button delegated its accessible name via
    # aria-labelledby to a sibling sr-only span inside a broadcast frame
    # so notification arrivals could swap the count without detaching the
    # button. D1 moves notifications off the avatar entirely — the avatar
    # carries a static identity-only aria-label.
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).not_to include('aria-labelledby="user_menu_button_label"')
  end

  it "nests the avatar image inside the button" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to include('id="user_avatar_header"')
  end

  it "does NOT render the legacy D1 bell-overlay markup (v2: replaced by a calm indicator dot)" do
    # Regression guard against re-introducing the D1 bell partials. The
    # indicator-v2 work removes notifications_bell_indicator_frame and
    # data-bell-severity entirely; if a future change brings them back,
    # this assertion catches it.
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).not_to include('notifications_bell_indicator_frame')
    expect(rendered).not_to include('data-bell-severity')
  end

  describe "notification indicator (v2)" do
    it "wraps the avatar in a relative inline-flex span so the indicator dot can position against it" do
      render partial: "shared/user_menu_avatar_button", locals: { user: user }
      expect(rendered).to match(%r{<span [^>]*id="user_avatar_header"[^>]*class="[^"]*\brelative\b[^"]*"})
      expect(rendered).to match(%r{<span [^>]*id="user_avatar_header"[^>]*class="[^"]*\binline-flex\b[^"]*"})
    end

    it "renders the indicator dot inside the avatar wrapper when the user has unread notifications" do
      PasswordChangedNotifier.with(record: user).deliver(user)
      render partial: "shared/user_menu_avatar_button", locals: { user: user }
      expect(rendered).to match(/data-severity="danger"/)
      expect(rendered).to match(/bg-danger-strong/)
    end

    it "renders no indicator dot when the user has no unread notifications" do
      render partial: "shared/user_menu_avatar_button", locals: { user: user }
      expect(rendered).not_to match(/data-severity=/)
    end
  end

  it "applies the AAA focus indicator (the focus-ring offset-outline utility)" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to match(/\bfocus-ring\b/)
  end

  it "renders a chevron-down affordance so the avatar reads as a menu trigger" do
    # Wathan's D1 design-panel note: a bare avatar reads as a static
    # identity badge, not as an interactive control. The chevron is the
    # universal "this opens a menu" hint and matches the workspace
    # switcher's pattern. data-test attribute provides a stable selector
    # without baking icon-internal SVG markup into the spec.
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to have_css('#user-menu-button [data-test="user-menu-chevron"]')
  end
end
