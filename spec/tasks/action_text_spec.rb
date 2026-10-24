require "rails_helper"
require "rake"

RSpec.describe "action_text rake tasks" do
  before(:all) { RakeTasks.load_once }

  def run_task(name)
    Rake::Task[name].reenable
    Rake::Task[name].invoke
  end

  describe "action_text:clear_filename_alts" do
    let(:blob) do
      ActiveStorage::Blob.create_and_upload!(io: Rails.root.join("spec/fixtures/files/avatar.png").open,
        filename: "IMG_2034.JPG", content_type: "image/png")
    end

    def document_with(alt:)
      attachment = ActionText::Attachment.from_attachable(blob, **{ alt: alt }.compact).to_html
      create(:document, body: "<p>Trip</p>#{attachment}<p>end</p>")
    end

    def stored_body(document)
      ActionText::RichText.connection.select_value(
        ActionText::RichText.where(id: document.rich_text_body.id).select(:body).to_sql
      )
    end

    def attachment_node(document)
      Nokogiri::HTML5.fragment(stored_body(document)).at_css("action-text-attachment")
    end

    it "removes an alt that is the attachment's own filename, and nothing else" do
      document = document_with(alt: "IMG_2034.JPG")

      expect { run_task("action_text:clear_filename_alts") }.to output(/1 rich text/).to_stdout

      node = attachment_node(document)
      expect(node["alt"]).to be_nil
      expect(node["filename"]).to eq("IMG_2034.JPG")
      expect(node["sgid"]).to be_present
      expect(Nokogiri::HTML5.fragment(stored_body(document)).text).to include("Trip", "end")
    end

    it "keeps an alt the author wrote" do
      document = document_with(alt: "A red canoe on a still lake")

      expect { run_task("action_text:clear_filename_alts") }.to output(/0 rich texts/).to_stdout

      expect(attachment_node(document)["alt"]).to eq("A red canoe on a still lake")
    end

    it "leaves an attachment without alt alone" do
      document = document_with(alt: nil)
      before = stored_body(document)

      run_task("action_text:clear_filename_alts")

      expect(stored_body(document)).to eq(before)
    end

    it "writes the body without touching timestamps or the record that owns it" do
      document = document_with(alt: "IMG_2034.JPG")
      rich_text = document.rich_text_body
      travel 1.day

      expect { run_task("action_text:clear_filename_alts") }
        .not_to(change { [ rich_text.reload.updated_at, document.reload.updated_at ] })
      expect(attachment_node(document)["alt"]).to be_nil
    end

    it "counts without writing when DRY_RUN is set" do
      document = document_with(alt: "IMG_2034.JPG")

      begin
        ENV["DRY_RUN"] = "1"
        expect { run_task("action_text:clear_filename_alts") }.to output(/1 rich text.*dry run/m).to_stdout
      ensure
        ENV.delete("DRY_RUN")
      end

      expect(attachment_node(document)["alt"]).to eq("IMG_2034.JPG")
    end

    it "cleans the stored body, so an edit saved after the row was loaded survives" do
      document = document_with(alt: "IMG_2034.JPG")
      loaded_before_the_edit = ActionText::RichText.find(document.rich_text_body.id)
      document.update!(body: "<p>Edited after loading</p>")
      allow(ActionText::RichText).to receive(:find_each).and_yield(loaded_before_the_edit)

      run_task("action_text:clear_filename_alts")

      expect(Nokogiri::HTML5.fragment(stored_body(document)).text).to include("Edited after loading")
    end

    it "finds nothing to change on a second run" do
      document_with(alt: "IMG_2034.JPG")
      run_task("action_text:clear_filename_alts")

      expect { run_task("action_text:clear_filename_alts") }.to output(/0 rich texts/).to_stdout
    end
  end
end
