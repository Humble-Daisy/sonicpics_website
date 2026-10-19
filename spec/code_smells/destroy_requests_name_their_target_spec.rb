require "rails_helper"

# A shared partial that takes its DELETE target as a local can be pointed at a parent's destroy (#1402).
# The census follows every URL local up to the template that names it. See /docs/developer/testing.
RSpec.describe "Code smell: destroy requests name their target" do
  unwalked = [
    "`render partial: ...` collection renders: their locals are not followed (the tree's four pass records, not URLs).",
    "A URL built in Ruby (a helper method, a component's .rb class) rather than written in a template.",
    "A hand-written <form> or <a> that spells the DELETE override in raw HTML instead of a helper option.",
    "A partial nothing renders: a DELETE whose URL is one of its locals resolves to no caller, so no site.",
    "A destroy that changes a record it did not load with `find`/`find_by` (a before_action's record): only a direct " \
      "`.discard!` is seen, and a model's verbs defined in a concern are not followed."
  ]

  # Top-level commas only: a nested call, hash, array or string keeps its commas.
  split_args = lambda do |text|
    parts = [ +"" ]
    depth = 0
    quote = nil
    text.each_char do |char|
      if quote
        quote = nil if char == quote
      elsif char == '"' || char == "'"
        quote = char
      elsif "([{".include?(char)
        depth += 1
      elsif ")]}".include?(char)
        depth -= 1
      elsif char == "," && depth.zero?
        parts << +""
        next
      end
      parts.last << char
    end
    parts.map(&:strip).reject(&:empty?)
  end

  parse_args = lambda do |rest|
    rest = rest.sub(/\s*\bdo\s*(\|[^|]*\|)?\s*\z/, "").strip
    rest = rest[1...-1] if rest.start_with?("(") && rest.end_with?(")")
    positional = []
    kwargs = {}
    split_args.call(rest).each do |arg|
      if (pair = arg.match(/\A(\w+):\s+(.*)\z/m))
        kwargs[pair[1]] = pair[2].strip
      else
        positional << arg
      end
    end
    { positional: positional, kwargs: kwargs }
  end

  erb_tags = lambda do |source|
    source.scan(/<%(?!#)(?:=|-)?(.*?)-?%>/m).map { |(code)| code.strip }
  end

  declared_locals = lambda do |source|
    list = source[/<%#\s*locals:\s*\((.*?)\)\s*-?%>/m, 1]
    next({}) unless list

    split_args.call(list).to_h do |entry|
      name, default = entry.split(":", 2).map(&:strip)
      [ name, default.to_s.empty? ? nil : default ]
    end
  end

  partial_file = lambda do |name, from|
    dir, base = name.include?("/") ? [ File.dirname(name), File.basename(name) ] : [ File.dirname(from).delete_prefix("app/views/"), name ]
    "app/views/#{dir}/_#{base}.html.erb"
  end

  # One request-making call per tag: the helper, then where its URL and its method sit.
  request_call = lambda do |code|
    helper = code[/\b(button_to|link_to|form_with|form_tag)\b/, 1]
    next unless helper

    args = parse_args.call(code.split(/\b#{helper}\b/, 2).last)
    block = code.match?(/\bdo\s*(\|[^|]*\|)?\s*\z/)
    url = case helper
    when "form_with" then args[:kwargs]["url"]
    when "form_tag" then args[:positional][0]
    else block ? args[:positional][0] : args[:positional][1]
    end
    method = args[:kwargs]["method"] ||
             args[:kwargs].values_at("data", "form").join(" ")[/turbo_method:\s*([^,}\s]+)/, 1]
    { helper: helper, url: url, method: method, confirmed: code.match?(/\bturbo_confirm:/) }
  end

  route_name = lambda do |expr|
    name = expr.to_s[/\A(?:main_app\.)?(\w+)_(?:path|url)\b/, 1]
    name if name && Rails.application.routes.named_routes.key?(name.to_sym)
  end

  delete_action = lambda do |name|
    named = Rails.application.routes.named_routes.get(name.to_s.to_sym)
    next unless named

    spec = named.path.spec.to_s
    route = Rails.application.routes.routes.find { |r| r.verb == "DELETE" && r.path.spec.to_s == spec }
    route && "#{route.defaults[:controller]}##{route.defaults[:action]}"
  end

  # Every request a template can make, resolved through each render chain to the URL and method its
  # outermost caller names. Takes {path => source} so the negative control can rewrite one template.
  census = lambda do |sources|
    locals = sources.transform_values { |source| declared_locals.call(source) }
    callers = Hash.new { |hash, key| hash[key] = [] }
    sources.each do |path, source|
      erb_tags.call(source).each do |code|
        next unless (found = code.match(/\Arender\s*\(?\s*["']([\w\/]+)["']\s*,?(.*)\z/m))

        callers[partial_file.call(found[1], path)] << { from: path, kwargs: parse_args.call(found[2])[:kwargs] }
      end
    end

    local_of = ->(expr, path) { locals.fetch(path, {}).key?(expr.to_s) }
    resolve = lambda do |url, method, path, chain|
      next [ { chain: chain, url: url, method: method, stuck: "render chain deeper than 8" } ] if chain.size > 8
      next [ { chain: chain, url: url, method: method } ] unless local_of.call(url, path) || local_of.call(method, path)

      callers[path].flat_map do |caller|
        pick = lambda do |expr|
          next expr unless local_of.call(expr, path)

          caller[:kwargs].fetch(expr) { locals[path][expr] }
        end
        resolve.call(pick.call(url), pick.call(method), caller[:from], [ caller[:from] ] + chain)
      end
    end

    sources.flat_map do |path, source|
      erb_tags.call(source).filter_map { |code| request_call.call(code) }.flat_map do |call|
        resolve.call(call[:url], call[:method], path, [ path ]).map { |entry| entry.merge(call.slice(:helper, :confirmed)) }
      end
    end
  end

  deletes = lambda do |entries|
    entries.select { |entry| entry[:method].to_s.match?(/\A(:delete|["']delete["'])\z/) || entry[:method].to_s.match?(/\A[a-z_]+\z/) }
  end

  nodes = lambda do |root|
    Enumerator.new do |out|
      stack = [ root ]
      while (node = stack.pop)
        out << node
        stack.concat(node.compact_child_nodes)
      end
    end
  end

  discarding_verbs = lambda do |model|
    calls = nodes.call(Prism.parse_file(Object.const_source_location(model.name).first).value)
      .grep(Prism::DefNode).to_h { |definition| [ definition.name, nodes.call(definition).grep(Prism::CallNode).map(&:name).to_set ] }
    verbs = Set[:discard!]
    loop do
      grown = verbs | calls.select { |_name, called| called.intersect?(verbs) }.keys
      break verbs if grown == verbs

      verbs = grown
    end
  end

  loaded_models = lambda do |destroy|
    Rails.application.eager_load!
    names = nodes.call(destroy).grep(Prism::CallNode).select { |call| %i[find find_by find_by!].include?(call.name) }.flat_map do |call|
      Enumerator.produce(call.receiver) { |link| link.respond_to?(:receiver) ? link.receiver : raise(StopIteration) }
        .take_while(&:itself).map { |link| link.is_a?(Prism::CallNode) ? link.name.to_s : link.slice }
    end
    names.flat_map do |name|
      [ name.safe_constantize ] + ApplicationRecord.descendants.filter_map { |model| model.reflect_on_association(name)&.klass rescue nil }
    end.select { |model| model.is_a?(Class) && model < ApplicationRecord }.uniq
  end

  soft_deleting = lambda do
    Dir[Rails.root.join("app/controllers/**/*_controller.rb")].filter_map do |file|
      destroy = nodes.call(Prism.parse_file(file).value).find { |node| node.is_a?(Prism::DefNode) && node.name == :destroy }
      next unless destroy

      verbs = loaded_models.call(destroy).map { |model| discarding_verbs.call(model) }.reduce(Set[:discard!], :|)
      next unless nodes.call(destroy).grep(Prism::CallNode).map(&:name).intersect?(verbs.to_a)

      "#{file.delete_prefix("#{Rails.root}/app/controllers/").delete_suffix("_controller.rb")}#destroy"
    end
  end

  tree = lambda do
    Dir[Rails.root.join("{app/views,app/components}/**/*.erb")].sort.to_h do |file|
      [ file.delete_prefix("#{Rails.root}/"), File.read(file) ]
    end
  end

  site = ->(entry) { "#{entry[:chain].join(' > ')} #{entry[:helper]} #{entry[:url]}" }

  let(:sources) { tree.call }
  let(:found) { deletes.call(census.call(sources)) }
  let(:discarding) { soft_deleting.call }

  it "sends every DELETE to a named route that has a DELETE action" do
    unresolved = found.reject { |entry| route_name.call(entry[:url]) && delete_action.call(route_name.call(entry[:url])) && !entry[:stuck] }

    expect(unresolved.map { |entry| site.call(entry) }).to be_empty,
      "These DELETE requests have a target the census cannot read as a route with a DELETE action:\n  " \
      "#{unresolved.map { |entry| site.call(entry) }.join("\n  ")}\n" \
      "fix: pass a route helper (`workspace_logo_path(workspace)`), not a variable, method call or bare path, " \
      "and check the route defines destroy.\nrule: /docs/developer/identity-system (Removing an Image), #1402\n" \
      "blind spots:\n  - #{unwalked.join("\n  - ")}"
  end

  unconfirmed_discards = lambda do |entries, discarding_actions|
    entries.select do |entry|
      name = route_name.call(entry[:url])
      name && discarding_actions.include?(delete_action.call(name)) && !entry[:confirmed] &&
        entry[:chain].exclude?("app/views/shared/_confirm_dialog.html.erb")
    end
  end

  it "sends a DELETE that discards a record only after a confirmation" do
    unconfirmed = unconfirmed_discards.call(found, discarding)

    expect(unconfirmed.map { |entry| "#{site.call(entry)} -> #{delete_action.call(route_name.call(entry[:url]))}" }).to be_empty,
      "These DELETE requests discard a record without a confirm dialog — the shape of #1402, where Remove photo " \
      "discarded the workspace:\n  #{unconfirmed.map { |entry| site.call(entry) }.join("\n  ")}\n" \
      "fix: point the control at the child resource it names, or confirm the destroy with shared/confirm_dialog " \
      "(or turbo_confirm).\n" \
      "rule: /docs/developer/identity-system (Removing an Image)\nblind spots:\n  - #{unwalked.join("\n  - ")}"
  end

  it "finds at least as many DELETE requests as it was written against" do
    expect(found.size).to be >= 34
  end

  it "follows the identity picker's Remove through both partials to the resource it names" do
    resolved = found.to_h { |entry| [ entry[:chain], delete_action.call(route_name.call(entry[:url]).to_s) ] }

    expect(resolved[%w[app/views/workspaces/_profile_section.html.erb app/views/shared/_identity_picker.html.erb
                       app/views/shared/identity_picker/_crop_footer.html.erb]]).to eq("workspaces/logos#destroy")
    expect(resolved[%w[app/views/settings/profiles/edit.html.erb app/views/shared/_identity_picker.html.erb
                       app/views/shared/identity_picker/_crop_footer.html.erb]]).to eq("settings/avatars#destroy")
  end

  it "reaches the workspace's destroy only through the danger zone's confirm dialog" do
    to_workspace = found.select { |entry| route_name.call(entry[:url]) && delete_action.call(route_name.call(entry[:url])) == "workspaces#destroy" }

    expect(to_workspace.map { |entry| entry[:chain] })
      .to eq([ %w[app/views/workspaces/settings/_danger_zone_section.html.erb app/views/shared/_confirm_dialog.html.erb] ])
  end

  it "derives the discarding destroys from the controllers and the models they load" do
    expect(discarding).to include("workspaces#destroy", "workspaces/projects#destroy",
                                  "workspaces/members#destroy", "operations/operatorships#destroy")
    expect(discarding).not_to include("workspaces/invitations#destroy", "workspaces/join_links#destroy"),
      "Invitation#revoke! and WorkspaceJoinLink#revoke! only change a status; sharing Operatorship#revoke!'s name " \
      "must not make them discards"
  end

  it "catches a Leave button that loses its turbo_confirm" do
    leave = "app/views/workspaces/_leave_button.html.erb"
    planted = sources.merge(leave => sources.fetch(leave).sub(/^\s*data: \{ turbo_confirm: .*\n/, ""))
    expect(planted.fetch(leave)).not_to eq(sources.fetch(leave)), "the injection point moved; the simulation proves nothing"

    expect(unconfirmed_discards.call(deletes.call(census.call(planted)), discarding).map { |entry| entry[:chain].first })
      .to include(leave)
  end

  it "catches #1402: Remove photo on the Profile page pointed at the workspace" do
    profile = "app/views/workspaces/_profile_section.html.erb"
    planted = sources.merge(profile => sources.fetch(profile).sub("remove_url: workspace_logo_path(workspace)", "remove_url: workspace_path(workspace)"))
    expect(planted.fetch(profile)).not_to eq(sources.fetch(profile)), "the injection point moved; the simulation proves nothing"

    reached = deletes.call(census.call(planted)).select do |entry|
      entry[:chain].first == profile && delete_action.call(route_name.call(entry[:url]).to_s) == "workspaces#destroy"
    end

    expect(reached.size).to eq(1)
    expect(reached.first[:chain]).not_to include("app/views/shared/_confirm_dialog.html.erb")
  end
end
