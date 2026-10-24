namespace :action_text do
  desc "Remove image alt text that Lexxy 0.9 set to the file's own name (DRY_RUN=1 counts without writing)"
  task clear_filename_alts: :environment do
    dry_run = ENV["DRY_RUN"].present?
    changed = 0

    ActionText::RichText.find_each do |rich_text|
      rich_text.with_lock do
        fragment = rich_text.body&.fragment or next
        filename_alts = fragment.find_all("action-text-attachment[alt]").select { |node| node["alt"] == node["filename"] }
        next if filename_alts.empty?

        changed += 1
        next if dry_run

        filename_alts.each { |node| node.remove_attribute("alt") }
        # update_column: a data cleanup must not touch the owning record or its timestamps.
        rich_text.update_column(:body, fragment.to_html)
      end
    end

    puts "#{changed} #{"rich text".pluralize(changed)} #{dry_run ? "would change (dry run)" : "changed"}"
  end
end
