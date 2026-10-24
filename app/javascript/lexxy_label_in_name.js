// Lexxy names its ALT button "Alternative text", which fails WCAG 2.5.3 (basecamp/lexxy#1304).
// Lead the name with the word the button shows; it stops acting once Lexxy's own name contains it.
const SELECTOR = "button.lexxy-attachment-toolbar__alternative-text"

function rename(button) {
  const shown = button.textContent.trim()
  const name = button.getAttribute("aria-label") || ""
  const words = name.toLowerCase().split(/[^\p{L}\p{N}]+/u)
  if (shown && name && !words.includes(shown.toLowerCase())) {
    button.setAttribute("aria-label", `${shown}, ${name.toLowerCase()}`)
  }
}

new MutationObserver((records) => {
  for (const record of records) {
    for (const node of record.addedNodes) {
      if (node.nodeType !== Node.ELEMENT_NODE) continue
      if (node.matches(SELECTOR)) rename(node)
      node.querySelectorAll(SELECTOR).forEach(rename)
    }
  }
}).observe(document.documentElement, { childList: true, subtree: true })
