# Visual identity of a User (avatar) or Workspace (logo): one polymorphic
# surface over the differently-named attachment/source/color attributes, so
# shared views and the picker write flow never type-switch on the model.
# NOT OauthIdentity (same directory) — that is the *authentication* identity
# (provider/uid). Design: docs repo, specs/2026-08-12-identity-poro-design.md.
class Identity
  DEFAULT_HUE = 210

  Result = Struct.new(:success, :error, :error_message, keyword_init: true) do
    def success? = success
    def failure? = !success
  end

  def initialize(model)
    @model = model
  end

  def initials = model.initials
  def primary_color = model.primary_color
  def hue = primary_color || DEFAULT_HUE
  # The hue an initials render should carry: nil at the default so
  # UI::AvatarComponent's bg-interactive branch applies (#755 — one rule for
  # user avatars and workspace icons alike), the custom hue otherwise.
  def custom_hue = (primary_color if primary_color.present? && primary_color != DEFAULT_HUE)
  def image? = image.attached?
  def uploaded_image? = source == "upload" && image?
  # Remote-host images (gravatar) render with loading: "lazy"; same-origin
  # variants don't.
  def remote_image? = source == "gravatar"

  # The image URL this identity shows at the given pixel size — nil means
  # "render initials". The case-on-source lives here, on the object that owns
  # source, not in view helpers (#653). Upload variants need a URL resolver
  # with route context (the engine-context-safe main_app.url_for), which the
  # caller supplies as the block; gravatar URLs are absolute and bypass it.
  def image_url(size:, &variant_url)
    case source
    when "upload"
      variant_url.call(image.variant(resize_to_fill: [ size, size ])) if image?
    when "gravatar"
      # Consistency-gated (see UserIdentity#gravatar_url): nil when gravatar
      # left available_sources, so a stale source renders initials instead of
      # a permanently broken ?d=404 image.
      gravatar_url(size: size)
    end
  end

  def image_updated_at
    image? ? image.blob.created_at : nil
  end

  # Re-crop source: the original when stored, so quality isn't progressively
  # degraded; falls back to the cropped image for older records.
  def croppable_image
    image_original.attached? ? image_original : image
  end

  def gravatar_url(size: 256) = nil

  def resolve_source(requested)
    return source if requested.blank?
    available_sources.include?(requested) ? requested : source
  end

  # One save: everything lands or nothing does. Leaving "upload" IRREVERSIBLY purges both
  # attachments, only after that save succeeds. See /docs/developer/identity-system (Saving a change).
  def apply(image: nil, image_original: nil, crop_coordinates: nil, source: nil, color: nil, name: nil)
    incoming_image = image.presence
    incoming_original = image_original.presence
    incoming_crop = crop_coordinates.presence
    incoming_source = source.presence
    incoming_color = color.presence

    if (failure = source_guard(incoming_image, incoming_source))
      return failure
    end

    # Ahead of any assignment below: a misuse (e.g. User#identity.apply
    # with a name:) must raise before side effects, not after purging blobs.
    write_name(name) unless name.nil?

    if incoming_image
      assign_image(incoming_image)
      write_source("upload")
    end
    assign_image_original(incoming_original) if incoming_original
    apply_crop_metadata(incoming_crop) if incoming_crop

    switching_source = incoming_source && incoming_image.nil?
    write_source(incoming_source) if switching_source

    model.primary_color = incoming_color.to_i if incoming_color

    result = save_result
    purge_images if result.success? && switching_source && incoming_source != "upload"
    result
  end

  private

  attr_reader :model

  # name is workspace-only (User has no name attribute); the base
  # implementation raises so a mistaken user.identity.apply(name: ...) fails
  # loud with an intent-revealing message instead of a bare NoMethodError.
  def write_name(_value)
    raise ArgumentError, "name is not part of #{self.class.name} — workspace identities only"
  end

  # Extracted from #apply to satisfy Metrics/MethodLength (DES-15 ratchet);
  # behavior is unchanged from the design spec's single-save/Result contract.
  def save_result
    if model.save
      Result.new(success: true)
    else
      Result.new(success: false, error: :invalid,
                 error_message: model.errors.full_messages.to_sentence)
    end
  end

  def source_guard(image, source)
    unavailable =
      if image
        !available_sources.include?("upload")
      else
        source.present? && !available_sources.include?(source)
      end
    Result.new(success: false, error: :source_unavailable) if unavailable
  end

  def apply_crop_metadata(raw)
    coords = safe_parse_coordinates(raw)
    return unless coords
    return unless image_original.attached?

    blob = image_original.blob
    if blob.persisted?
      # Re-crop of an existing original: immediate metadata write. Can race a
      # concurrent purge (0 rows, no error) — accepted; worst case is default
      # framing on the next re-crop (design spec, write flow beat 3).
      blob.update!(metadata: blob.metadata.merge("crop" => coords))
    else
      blob.metadata = blob.metadata.merge("crop" => coords)
    end
  end

  # Purge keyed on the RESULTING source; prior source is irrelevant (a
  # gravatar-sourced user with a stale blob switching to initials still purges).
  def purge_images
    image.purge if image.attached?
    image_original.purge if image_original.attached?
  end

  def safe_parse_coordinates(raw)
    return nil if raw.blank?

    parsed = JSON.parse(raw)
    return nil unless parsed.is_a?(Hash)
    return nil unless %w[x y w h].all? { |k| parsed[k].is_a?(Numeric) }

    parsed.slice("x", "y", "w", "h")
  rescue JSON::ParserError
    nil
  end
end
