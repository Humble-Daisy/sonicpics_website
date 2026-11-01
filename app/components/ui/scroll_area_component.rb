# frozen_string_literal: true

module UI
  # A fixed-height (or fixed-width) scrollable container with a thin, themed scrollbar styled via CSS custom properties — no plugin needed under Tailwind v4.
  # Usage, options and the accessibility contract: docs/components/scroll_area.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class ScrollAreaComponent < ApplicationComponent
    ORIENTATIONS = {
      vertical:   "overflow-y-auto",
      horizontal: "overflow-x-auto",
      both:       "overflow-auto"
    }.freeze

    # Thin, themed scrollbar applied to the viewport (token-driven, no raw hex).
    SCROLLBAR_CLS = "[scrollbar-width:thin] " \
                    "[scrollbar-color:var(--color-border)_transparent] " \
                    "[&::-webkit-scrollbar]:w-1.5 [&::-webkit-scrollbar]:h-1.5 " \
                    "[&::-webkit-scrollbar-track]:bg-transparent " \
                    "[&::-webkit-scrollbar-thumb]:rounded-full " \
                    "[&::-webkit-scrollbar-thumb]:bg-border"

    # orientation:     :vertical (default) | :horizontal | :both
    # max_h:           Tailwind max-height class, e.g. "max-h-72" (vertical / both)
    # max_w:           Tailwind max-width class, e.g. "max-w-sm" (horizontal / both)
    # focusable:       make the region a keyboard tab stop (default true; opt out
    #                  only when the content is itself fully keyboard-reachable)
    # aria_label:      accessible name for the focusable region
    # aria_labelledby: id of an existing element that names the region
    def initialize(orientation: :vertical, max_h: "max-h-72", max_w: nil,
                   focusable: true, aria_label: nil, aria_labelledby: nil, **html_attrs)
      @orientation = orientation.to_sym
      @max_h = max_h
      @max_w = max_w
      @focusable = focusable
      @aria_label = aria_label
      @aria_labelledby = aria_labelledby
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      overflow = ORIENTATIONS.fetch(@orientation) do
        raise ArgumentError, "Unknown scroll_area orientation #{@orientation.inspect} (expected one of #{ORIENTATIONS.keys.inspect})"
      end

      # relative: an absolute child (an sr-only label) would otherwise escape the clip and widen the page.
      attrs = { class: cn("relative", overflow, SCROLLBAR_CLS, focus_cls, @max_h, @max_w, @extra_class) }
      attrs.merge!(region_attrs) if @focusable

      content_tag(:div, content, **attrs, **@html_attrs)
    end

    private

    # Only a focusable region needs (and gets) the visible focus indicator.
    def focus_cls
      @focusable ? "focus-ring" : nil
    end

    # A focusable scroll region MUST be named, or AT announces an anonymous "region".
    def region_attrs
      name = @aria_labelledby || @aria_label
      if name.nil?
        raise ArgumentError,
          "scroll_area is keyboard-focusable but has no accessible name — pass aria_label: or aria_labelledby: (or focusable: false if the content is itself fully keyboard-reachable)"
      end

      attrs = { tabindex: "0", role: "region" }
      if @aria_labelledby
        attrs[:"aria-labelledby"] = @aria_labelledby
      else
        attrs[:"aria-label"] = @aria_label
      end
      attrs
    end
  end
end
