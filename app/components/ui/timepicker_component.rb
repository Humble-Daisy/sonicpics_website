# frozen_string_literal: true

module UI
  # A disclosure button that opens a popover of hour/minute (and, in 12-hour mode, AM/PM) **spinbuttons**, driven by the `timepicker` Stimulus controller shipped alongside this component.
  # Usage, options and the accessibility contract: docs/components/timepicker.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class TimepickerComponent < ApplicationComponent
    WRAPPER  = "relative inline-block"
    HINT_CLS = "mt-1.5 block text-sm text-text-muted"
    TRIGGER  = "flex h-11 w-36 cursor-pointer items-center gap-2 rounded-md border border-border-strong " \
               "bg-surface-raised px-3 text-sm text-text-heading shadow-xs focus-ring motion-safe:transition " \
               "aria-expanded:border-border-focus"
    ICON_CLS = "size-4 shrink-0 text-text-muted"
    # Placement is CSS anchor positioning: `position: fixed` (containing block = the
    # viewport) tethered to the trigger via `anchor-name`/`position-anchor`. Being
    # viewport-positioned is what lets the panel be promoted to the top layer, so a
    # sticky/backdrop-blur ancestor cannot bury it (app/javascript/overlays/top_layer.js).
    POPOVER  = "z-50 hidden w-max max-w-[calc(100vw-2rem)] rounded-lg border border-border bg-surface-overlay p-3 shadow-md data-[open=true]:block mt-1 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_span-right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:left-0"
    SPINNER_WRAP = "flex items-center justify-center gap-1"
    COL_CLS  = "flex flex-col items-center gap-1"
    # size-11 (44px): steppers are aria-hidden to AT but remain POINTER
    # targets, and WCAG 2.5.5's floor applies to pointer targets regardless
    # of AT visibility (caught by the open-state audit, #463).
    SPIN_BTN = "inline-flex size-11 items-center justify-center rounded-md focus-ring " \
               "text-text-muted hover:bg-surface-sunken hover:text-text-heading motion-safe:transition"
    # min-h-input + w-12: the spinbutton fields are the primary targets and must
    # clear the 44px floor (WCAG 2.5.5 AAA — open-state audit, #463).
    NUM_CLS  = "w-12 min-h-input rounded-md border border-border-strong bg-surface-raised px-1 text-center text-sm focus-ring"
    SEP_CLS  = "text-lg font-medium text-text-heading pb-1"

    # The human-readable format hint, keyed by `format:`.
    FORMATS = {
      h24: { hint: "HH:MM (24-hour)" },
      h12: { hint: "HH:MM AM/PM (12-hour)" }
    }.freeze

    def initialize(value: nil, name: nil, label: nil, format: :h24, step: 1, **html_attrs)
      @value       = value
      @name        = name
      @format      = coerce_enum(:format, format, FORMATS)
      @label       = label || I18n.t("modelrails_ui.timepicker.label", default: "Pick time")
      @step        = step.to_i.clamp(1, 60)
      @id          = html_attrs.delete(:id) || "timepicker-#{SecureRandom.hex(4)}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      caller_data = @html_attrs.delete(:data) || {}
      content_tag(:div,
        class: cn(WRAPPER, @extra_class),
        style: "anchor-name: --#{@id}",
        data: {
          controller: "timepicker",
          timepicker_format_value: @format,
          timepicker_step_value: @step,
          timepicker_name_value: @label
        }.merge(caller_data),
        **@html_attrs) do
        concat hidden_input if @name
        concat trigger_button
        concat hint
        concat clock_popover
      end
    end

    private

    def trigger_id = "#{@id}-trigger"
    def popover_id = "#{@id}-popover"
    def hint_id    = "#{@id}-hint"

    def hour_max = @format == :h12 ? 12 : 23

    def format_hint = FORMATS.fetch(@format)[:hint]

    def hint
      content_tag(:span,
        I18n.t("modelrails_ui.timepicker.hint", pattern: format_hint, default: "Time format: %{pattern}"),
        id: hint_id, class: HINT_CLS)
    end

    def hidden_input
      tag.input(type: "hidden", name: @name,
        value: @value,
        data: { timepicker_target: "hidden" })
    end

    def trigger_button
      content_tag(:button, type: "button",
        id: trigger_id,
        class: TRIGGER,
        "aria-expanded": "false",
        "aria-haspopup": "dialog",
        "aria-controls": popover_id,
        "aria-label": [ @label, @value ].compact.join(", "),
        "aria-describedby": hint_id,
        data: {
          timepicker_target: "trigger",
          action: "click->timepicker#toggle"
        }) do
        concat clock_icon
        concat content_tag(:span, @value || @label, data: { timepicker_target: "label" })
      end
    end

    def clock_popover
      hour_val, min_val = (@value || "00:00").split(":").map(&:to_i)

      content_tag(:div,
        id: popover_id,
        class: POPOVER,
        style: "position-anchor: --#{@id}",
        role: "dialog",
        "aria-label": @label,
        "aria-modal": "true",
        tabindex: "-1",
        data: { timepicker_target: "popover" }) do
        content_tag(:div, class: SPINNER_WRAP) do
          concat hour_column(hour_val)
          concat content_tag(:span, ":", class: SEP_CLS, "aria-hidden": "true")
          concat minute_column(min_val)
          concat ampm_column if @format == :h12
        end
      end
    end

    def hour_column(val)
      content_tag(:div, class: COL_CLS) do
        concat spin_btn("▲", "click->timepicker#hourUp")
        concat spinbutton(:hour, val, 0, hour_max,
          label: I18n.t("modelrails_ui.timepicker.hour", default: "Hour"),
          action: "change->timepicker#hourChanged keydown->timepicker#hourKeydown")
        concat spin_btn("▼", "click->timepicker#hourDown")
      end
    end

    def minute_column(val)
      content_tag(:div, class: COL_CLS) do
        concat spin_btn("▲", "click->timepicker#minuteUp")
        concat spinbutton(:minute, val, 0, 59,
          label: I18n.t("modelrails_ui.timepicker.minute", default: "Minute"),
          action: "change->timepicker#minuteChanged keydown->timepicker#minuteKeydown")
        concat spin_btn("▼", "click->timepicker#minuteDown")
      end
    end

    def ampm_column
      content_tag(:div, class: COL_CLS) do
        concat spin_btn("▲", "click->timepicker#toggleAmPm")
        concat content_tag(:span, "AM",
          role: "spinbutton",
          tabindex: "0",
          "aria-label": I18n.t("modelrails_ui.timepicker.meridiem", default: "AM or PM"),
          "aria-valuetext": "AM",
          class: cn(NUM_CLS, "cursor-pointer select-none"),
          data: { timepicker_target: "ampm", action: "click->timepicker#toggleAmPm keydown->timepicker#ampmKeydown" })
        concat spin_btn("▼", "click->timepicker#toggleAmPm")
      end
    end

    # A real spinbutton: a numeric text field announced as role=spinbutton with the
    # full aria-value* set. The controller keeps aria-valuenow/aria-valuetext in sync.
    def spinbutton(target, val, min, max, label:, action:)
      tag.input(type: "text", inputmode: "numeric",
        class: NUM_CLS,
        role: "spinbutton",
        value: val.to_s.rjust(2, "0"),
        maxlength: "2",
        "aria-label": label,
        "aria-valuemin": min,
        "aria-valuemax": max,
        "aria-valuenow": val,
        "aria-valuetext": val.to_s.rjust(2, "0"),
        data: { timepicker_target: target, action: action })
    end

    # The ▲/▼ steppers are decorative: aria-hidden + tabindex=-1 so the spinbutton
    # inputs are the single keyboard/SR target (no duplicate announcements).
    def spin_btn(label, action)
      content_tag(:button, label, type: "button",
        class: SPIN_BTN, "aria-hidden": "true",
        tabindex: "-1", data: { action: action })
    end

    def clock_icon
      content_tag(:svg,
        safe_join([
          content_tag(:circle, nil, cx: "12", cy: "12", r: "10"),
          content_tag(:polyline, nil, points: "12 6 12 12 16 14")
        ]),
        xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24",
        fill: "none", stroke: "currentColor", "stroke-width": "2",
        "stroke-linecap": "round", "stroke-linejoin": "round",
        class: ICON_CLS, "aria-hidden": "true")
    end

    def coerce_enum(name, value, map)
      key = value.to_sym
      return key if map.key?(key)

      raise ArgumentError,
        "UI::Timepicker unknown #{name}: #{value.inspect} (allowed: #{map.keys.join(", ")})"
    end
  end
end
