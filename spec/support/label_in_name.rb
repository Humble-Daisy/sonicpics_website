# WCAG 2.5.3 Label in Name, as axe's label-content-name-mismatch checks it: the name holds the visible words, in order.
RSpec::Matchers.define :contain_visible_text do |visible|
  unbracketed = ->(text) { (stripped = text.gsub(/\([^()]*\)/, "")) == text ? text : unbracketed.call(stripped) }
  words = ->(text) { unbracketed.call(text.to_s).downcase.gsub(/[^\p{L}\p{N}]+/, " ").split }

  match do |name|
    shown = words.call(visible)
    shown.empty? || words.call(name).each_cons(shown.size).include?(shown)
  end

  failure_message { |name| "expected the name #{name.inspect} to contain the visible text #{visible.inspect}" }
end
