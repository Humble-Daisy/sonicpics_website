require "rails_helper"
require "nokogiri"

RSpec.describe "The releasing guide's flow diagram" do
  let(:source) { Rails.root.join("app/docs/developer/releasing.md").read }
  let(:svgs) { source.scan(/<svg\b.*?<\/svg>/m).map { |svg| Nokogiri::XML(svg) { |config| config.strict }.root } }
  let(:wide) { svgs.find { |svg| svg["class"].to_s.split.include?("md:block") } }
  let(:narrow) { svgs.find { |svg| svg["class"].to_s.split.include?("md:hidden") } }
  let(:smallest_phone_width) { 264 }
  let(:narrowest_column_with_sidebar) { 565 }

  it "draws a wide version from tablet width up and a narrow one below it" do
    expect(svgs.size).to eq(2)
    expect(wide["class"].split).to include("hidden")
    expect(narrow["class"].split).to include("max-w-xs")
  end

  it "colors each version only with token classes the stylesheet already compiles" do
    layout = %w[hidden md:block md:hidden max-w-xs mx-auto]
    tokens = %w[text-accent text-info text-warning text-success text-surface-raised]

    svgs.each do |svg|
      used = svg.css("[class]").flat_map { |node| node["class"].split }.uniq
      expect(used - layout - tokens).to be_empty
      expect(used).to include("text-info", "text-warning", "text-success")
    end
  end

  it "follows one story, #1487, through every stop on desktop" do
    expect(wide.css("text").map(&:text).join(" ")).to include("#1487").and include("New onboarding flow").and include("LIVE")
  end

  it "names both versions for assistive tech" do
    svgs.each do |svg|
      expect(svg["role"]).to eq("img")
      expect(svg["aria-label"]).to include("next").and include("staging").and include("production")
    end
  end

  it "heads each stop with its branch, with the book analogy beside it" do
    svgs.each do |svg|
      headings = svg.css('text[font-weight="700"]').map(&:text)

      expect(headings).to include("your branch", "next", "release/<name>", "main")
      expect(svg.css("text").map(&:text)).to include("The draft", "The pile", "The book", "Published")
      expect(headings).not_to include("The draft", "The pile", "The book", "Published")
    end
  end

  it "calls the hand checks what the PR template calls them, never Try it" do
    expect(source).not_to include("Try it")
  end

  it "sets every word at 12px or more, the narrow version on a 360px phone and the wide one beside the docs sidebar" do
    { narrow => smallest_phone_width, wide => narrowest_column_with_sidebar }.each do |svg, width|
      expect(svg.css("[transform]").map { |node| node["transform"] }).to all(satisfy { |transform| !transform.match?(/scale|matrix/) })
      scale = width / svg["viewBox"].split[2].to_f

      svg.css("text").each do |text|
        font_size = text.ancestors.grep(Nokogiri::XML::Element).unshift(text).find { |node| node["font-size"] }&.[]("font-size") || 16
        rendered = font_size.to_f * scale
        expect(rendered).to be >= 12, "#{text.text.inspect} renders at #{rendered.round(1)}px"
      end
    end
  end

  it "gives each version its own arrowhead, so the hidden one can't take the visible one's" do
    markers = svgs.flat_map { |svg| svg.css("marker").map { |marker| marker["id"] } }

    expect(markers.uniq.size).to eq(svgs.size)
  end

  it "survives the markdowndocs renderer with every stage drawn in each version" do
    rendered = Nokogiri::HTML5.fragment(Markdowndocs::MarkdownRenderer.render(source.sub(/\A---\n.*?\n---\n/m, "")))
    drawn = rendered.css("svg")

    expect(drawn.size).to eq(2)
    drawn.each do |svg|
      expect(svg.css("text").map(&:text)).to include("your branch", "next", "release/<name>", "main")
    end
    expect(rendered.css("rect, path, line").reject { |node| node.ancestors("svg").any? }).to be_empty
  end
end
