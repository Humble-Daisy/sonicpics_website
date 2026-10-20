import { Controller } from "@hotwired/stimulus"
import * as topLayer from "overlays/top_layer"

export default class extends Controller {
  static targets = ["trigger", "popover", "label", "hidden", "hour", "minute", "ampm"]
  static values = {
    format: { type: String, default: "h24" },
    step:   { type: Number, default: 1 },
    name:   String
  }

  connect() {
    this.#outsideHandler = (e) => {
      if (!this.element.contains(e.target)) this.close()
    }
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    // No-op unless anchor-positioned (`position: fixed`); top_layer.js refuses the
    // pre-Baseline `absolute` fallback, where promotion would tear the panel off-screen.
    this.popoverTarget.dataset.open = "true"
    topLayer.enable(this.popoverTarget)
    topLayer.show(this.popoverTarget)
    this.triggerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.#outsideHandler)
    this.isOpen = true
  }

  close() {
    topLayer.hide(this.popoverTarget)
    topLayer.disable(this.popoverTarget)
    this.popoverTarget.dataset.open = "false"
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.#outsideHandler)
    this.isOpen = false
  }

  hourUp()   { this.#stepHour(1) }
  hourDown() { this.#stepHour(-1) }

  minuteUp()   { this.#stepMinute(this.stepValue) }
  minuteDown() { this.#stepMinute(-this.stepValue) }

  // ↑/↓ on the hour and minute spinbuttons, routed through the same methods the ▲/▼
  // steppers call so wrap-around, `step:` and the aria-value* sync cannot diverge
  // between the two paths (#219).
  hourKeydown(e)   { this.#arrowStep(e, () => this.hourUp(), () => this.hourDown()) }
  minuteKeydown(e) { this.#arrowStep(e, () => this.minuteUp(), () => this.minuteDown()) }

  // ↑/↓ on the AM/PM spinbutton toggle it (the role=spinbutton keyboard contract).
  ampmKeydown(e) {
    if (e.key === "ArrowUp" || e.key === "ArrowDown") {
      e.preventDefault()
      this.toggleAmPm()
    }
  }

  toggleAmPm() {
    if (!this.hasAmpmTarget) return
    const current = this.ampmTarget.textContent.trim()
    const next = current === "AM" ? "PM" : "AM"
    this.ampmTarget.textContent = next
    this.ampmTarget.setAttribute("aria-valuetext", next)
    this.#commit()
  }

  hourChanged()   { this.#clampInput(this.hourTarget, 0, this.formatValue === "h12" ? 12 : 23); this.#commit() }
  minuteChanged() { this.#clampInput(this.minuteTarget, 0, 59); this.#commit() }

  #arrowStep(event, up, down) {
    if (event.key === "ArrowUp") { event.preventDefault(); up() }
    else if (event.key === "ArrowDown") { event.preventDefault(); down() }
  }

  #stepHour(delta) {
    const max = this.formatValue === "h12" ? 12 : 23
    let val = parseInt(this.hourTarget.value || "0", 10) + delta
    if (val > max) val = 0
    if (val < 0)   val = max
    this.hourTarget.value = String(val).padStart(2, "0")
    this.#syncSpinbutton(this.hourTarget)
    this.#commit()
  }

  #stepMinute(delta) {
    let val = parseInt(this.minuteTarget.value || "0", 10) + delta
    if (val > 59) val = 0
    if (val < 0)  val = 59
    this.minuteTarget.value = String(val).padStart(2, "0")
    this.#syncSpinbutton(this.minuteTarget)
    this.#commit()
  }

  #clampInput(input, min, max) {
    let val = parseInt(input.value || "0", 10)
    if (isNaN(val)) val = min
    val = Math.min(max, Math.max(min, val))
    input.value = String(val).padStart(2, "0")
    this.#syncSpinbutton(input)
  }

  // Mirror the field's numeric value onto the role=spinbutton aria-value* contract so
  // screen readers announce the current value, not stale markup.
  #syncSpinbutton(input) {
    const display = input.value.padStart(2, "0")
    input.setAttribute("aria-valuenow", parseInt(display, 10))
    input.setAttribute("aria-valuetext", display)
  }

  #commit() {
    const h = this.hourTarget.value.padStart(2, "0")
    const m = this.minuteTarget.value.padStart(2, "0")
    const ampm = this.hasAmpmTarget ? ` ${this.ampmTarget.textContent.trim()}` : ""
    const display = `${h}:${m}${ampm}`
    const hidden  = `${h}:${m}`

    this.labelTarget.textContent = display
    this.triggerTarget.setAttribute("aria-label", `${this.nameValue}, ${display}`)
    if (this.hasHiddenTarget) this.hiddenTarget.value = hidden

    this.element.dispatchEvent(new CustomEvent("timepicker:change", {
      detail: { time: hidden },
      bubbles: true
    }))
  }

  #outsideHandler = null
  isOpen = false
}
