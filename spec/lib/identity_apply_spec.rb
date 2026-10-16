require "rails_helper"

RSpec.describe "Identity#apply" do
  let(:png) { fixture_file_upload("avatar.png", "image/png") }
  let(:png2) { fixture_file_upload("avatar.png", "image/png") }

  describe UserIdentity do
    let(:user) { create(:user) }
    let(:identity) { user.identity }

    describe "source guard" do
      it "fails with :source_unavailable and no side effects for an unavailable source" do
        result = identity.apply(source: "gravatar") # no gravatar on a fresh user
        expect(result).not_to be_success
        expect(result.error).to eq(:source_unavailable)
        expect(user.reload.avatar_source).to eq("initials")
      end

      it "fails when a file is sent but upload is not an available source" do
        allow(user).to receive(:available_avatar_sources).and_return(%w[gravatar initials])
        result = identity.apply(image: png)
        expect(result.error).to eq(:source_unavailable)
        expect(user.reload.avatar).not_to be_attached
      end

      it "lets a file upload win over a stale unavailable source param (upload-wins)" do
        result = identity.apply(image: png, source: "gravatar")
        expect(result).to be_success
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_source).to eq("upload")
      end
    end

    describe "attach beats" do
      it "assigns image + original and sets source to upload in one save" do
        result = identity.apply(image: png, image_original: png2)
        expect(result).to be_success
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_original).to be_attached
        expect(user.avatar_source).to eq("upload")
      end
    end

    describe "crop metadata" do
      it "persists coordinates onto a newly attached original via the single save" do
        identity.apply(image: png, image_original: png2, crop_coordinates: '{"x":1,"y":2,"w":3,"h":4}')
        expect(user.reload.avatar_original.blob.metadata["crop"])
          .to eq("x" => 1, "y" => 2, "w" => 3, "h" => 4)
      end

      it "updates the persisted original's blob on a re-crop (no new original sent)" do
        user = create(:user, :with_avatar)
        result = user.identity.apply(image: png, crop_coordinates: '{"x":5,"y":6,"w":7,"h":8}')
        expect(result).to be_success
        expect(user.reload.avatar_original.blob.metadata["crop"])
          .to eq("x" => 5, "y" => 6, "w" => 7, "h" => 8)
      end

      it "ignores malformed JSON without failing" do
        result = identity.apply(image: png, image_original: png2, crop_coordinates: "not-json{")
        expect(result).to be_success
        expect(user.reload.avatar_original.blob.metadata["crop"]).to be_nil
      end

      it "ignores coordinates missing required keys" do
        result = identity.apply(image: png, image_original: png2, crop_coordinates: '{"foo":1}')
        expect(result).to be_success
        expect(user.reload.avatar_original.blob.metadata["crop"]).to be_nil
      end

      it "ignores non-numeric coordinate values" do
        result = identity.apply(image: png, image_original: png2, crop_coordinates: '{"x":"a","y":"b","w":"c","h":"d"}')
        expect(result).to be_success
        expect(user.reload.avatar_original.blob.metadata["crop"]).to be_nil
      end

      it "ignores coordinates when no original is in play" do
        result = identity.apply(source: "initials", crop_coordinates: '{"x":1,"y":2,"w":3,"h":4}')
        expect(result).to be_success
      end
    end

    describe "source switch" do
      it "purges both attachments when the resulting source is not upload — regardless of prior source" do
        user = create(:user, :with_avatar)
        user.update_columns(avatar_source: "gravatar") # prior source is NOT upload
        result = user.identity.apply(source: "initials")
        expect(result).to be_success
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_original).not_to be_attached
        expect(user.avatar_source).to eq("initials")
      end

      it "keeps both attachments and their files when the save fails" do
        user = create(:user, :with_avatar)
        user.update_columns(primary_color: 999)
        keys = [ user.avatar.blob.key, user.avatar_original.blob.key ]

        result = user.identity.apply(source: "initials")

        expect(result).not_to be_success
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_original).to be_attached
        expect(user.avatar_source).to eq("upload")
        expect(keys.map { |key| ActiveStorage::Blob.service.exist?(key) }).to eq([ true, true ])
      end

      it "does not purge when switching TO upload" do
        user = create(:user, :with_avatar)
        result = user.identity.apply(source: "upload")
        expect(result).to be_success
        expect(user.reload.avatar).to be_attached
      end
    end

    describe "color and blank handling" do
      it "assigns primary_color from a string" do
        expect(identity.apply(source: "initials", color: "270")).to be_success
        expect(user.reload.primary_color).to eq(270)
      end

      it "treats blank source and color as absent" do
        result = identity.apply(source: "", color: "")
        expect(result).to be_success
        expect(user.reload.avatar_source).to eq("initials")
      end
    end

    describe "failure" do
      it "returns :invalid with the errors sentence and persists nothing" do
        result = identity.apply(image: png, image_original: png2, color: "999")
        expect(result).not_to be_success
        expect(result.error).to eq(:invalid)
        expect(result.error_message).to be_present
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_original).not_to be_attached
        expect(user.primary_color).not_to eq(999)
      end

      it "leaves a prior avatar intact when a replacement fails (single-save semantics)" do
        user = create(:user, :with_avatar)
        old_blob_id = user.avatar.blob.id
        result = user.identity.apply(image: png, color: "999")
        expect(result).not_to be_success
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar.blob.id).to eq(old_blob_id)
      end
    end

    describe "name" do
      it "raises for a user identity — name is workspace-only" do
        expect { user.identity.apply(name: "x") }.to raise_error(ArgumentError, /name is not part of/)
      end
    end
  end

  describe WorkspaceIdentity do
    let(:workspace) { create(:workspace) }
    let(:identity) { workspace.identity }

    it "maps the write flow onto logo attributes" do
      result = identity.apply(image: png, image_original: png2, crop_coordinates: '{"x":1,"y":2,"w":3,"h":4}')
      expect(result).to be_success
      workspace.reload
      expect(workspace.logo).to be_attached
      expect(workspace.logo_original).to be_attached
      expect(workspace.logo_source).to eq("upload")
      expect(workspace.logo_original.blob.metadata["crop"]).to eq("x" => 1, "y" => 2, "w" => 3, "h" => 4)
    end

    it "owns name: assigns it into the same save" do
      result = identity.apply(source: "initials", color: "200", name: "Renamed Rockets")
      expect(result).to be_success
      workspace.reload
      expect(workspace.name).to eq("Renamed Rockets")
      expect(workspace.primary_color).to eq(200)
    end

    it "fails the whole apply when name is blank — nothing persists" do
      result = identity.apply(image: png, name: "")
      expect(result).not_to be_success
      expect(result.error).to eq(:invalid)
      workspace.reload
      expect(workspace.logo).not_to be_attached
      expect(workspace.name).to be_present
    end

    it "treats nil name as absent" do
      expect(identity.apply(source: "initials", name: nil)).to be_success
    end

    it "rejects gravatar as a source" do
      expect(identity.apply(source: "gravatar").error).to eq(:source_unavailable)
    end
  end
end
