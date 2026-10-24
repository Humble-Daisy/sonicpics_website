class NotificationMailer < ApplicationMailer
  # A suspended user gets no mail they cannot act on (#1132). response_body, not
  # throw :abort: a before_action's throw is uncaught on Rails 8.1.
  before_action :abort_when_recipient_suspended

  # Mailer methods invoked by Noticed via `deliver_by :email, mailer: ..., method: ...`.
  # Noticed dispatches through ActionMailer's parameterized API:
  #   NotificationMailer.with(notification:, record:, recipient:, **event_params).workspace_role_changed
  # so each method reads from `params[:notification]` / `params[:record]` / `params[:recipient]`
  # rather than taking positional arguments. See Noticed::DeliveryMethods::Email for the exact
  # call shape.
  #
  # Convention: the locale subject lives at notification_mailer.<method>.subject
  # with any positional substitutions documented in the per-method signature.

  def workspace_role_changed
    @notification = params[:notification]
    @recipient = params[:recipient]
    @membership = params[:record]
    @workspace = @membership.workspace
    @role = @membership.role

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_role_changed.subject",
                 workspace_name: @workspace.name)
    )
  end

  def workspace_invitation_expiring_soon
    @notification = params[:notification]
    @recipient = params[:recipient]
    @invitation = params[:record]
    # Delivery-time gate, the reminder's final hop: noticed's before_enqueue
    # runs at EventJob time, so a block landing between dispatch and render is
    # only catchable here (PR 4 spec §8.3 site 6 / Departure 3). No mail call →
    # NullMail → no delivery.
    return unless @invitation.deliverable?
    @workspace = @invitation.resolved_workspace
    @hours_remaining = @invitation.expires_in_hours
    @accept_url = accept_invitation_url(token: @invitation.token)

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_invitation_expiring_soon.subject",
                 workspace_name: @workspace.name)
    )
  end

  def workspace_member_added
    @notification = params[:notification]
    @recipient = params[:recipient]
    @membership = params[:record]
    @workspace = @membership.workspace
    @role = @membership.role

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_member_added.subject",
                 workspace_name: @workspace.name)
    )
  end

  # The removal notice. Only the removed member is ever sent one — the
  # notifier's before_enqueue drops every other recipient — so this is the one
  # place the event speaks in the second person.
  def workspace_member_removed
    @notification = params[:notification]
    @recipient = params[:recipient]
    @membership = params[:record]
    @workspace = @membership.workspace

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_member_removed.subject",
                 workspace_name: @workspace.name)
    )
  end

  # Billing alert: a workspace has crossed the 80%-of-capacity threshold for a
  # given metric. notification.params carries `:metric`, `:current`, `:limit`
  # from WorkspaceCapacityApproachingNotifier.with(...).
  #
  # Per-recipient throttle (EmailRecipientThrottle): even though billing is not
  # a security category, capacity alerts for a busy workspace can dispatch to
  # multiple owners simultaneously. The throttle caps repeated sends to a
  # single recipient (e.g., an owner who owns many workspaces, all of which
  # cross the threshold on the same sweep run). Fail-open on cache miss so a
  # cache outage doesn't suppress legitimate alerts.
  def workspace_capacity_approaching
    @notification = params[:notification]
    @recipient = params[:recipient]
    @workspace = params[:record]
    @metric = @notification&.params&.dig(:metric) || @notification&.params&.dig("metric")
    @current = @notification&.params&.dig(:current) || @notification&.params&.dig("current")
    @limit = @notification&.params&.dig(:limit) || @notification&.params&.dig("limit")
    @settings_url = edit_workspace_settings_url(@workspace)

    return unless EmailRecipientThrottle.allow!(@recipient.email_address, kind: :workspace_capacity_approaching)

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_capacity_approaching.subject",
                 workspace_name: @workspace.name,
                 metric: @metric)
    )
  end

  # Security alert: a sign-in arrived from a (user_agent, os) digest we haven't
  # seen for this user. The notification.params hash carries `:user_agent` and
  # `:os` from SignInFromNewDeviceNotifier.with(...).
  #
  # Per-recipient throttle (EmailRecipientThrottle): mirrors the pattern in
  # OmniauthCallbacksController#handle_existing_auth — even security-category
  # mail is gated by per-recipient flood protection so a coordinated attack
  # can't flood a single inbox by triggering many novel-device sign-ins. The
  # throttle is checked here (inside the mailer method) rather than at the
  # Notifier callsite because Noticed dispatches via deliver_later through its
  # own job pipeline, not directly through deliver_later from a controller.
  # The throttle fails open if Rails.cache.increment is unavailable, so a
  # cache outage doesn't suppress security alerts.
  def sign_in_from_new_device
    @notification = params[:notification]
    @recipient = params[:recipient]
    @user = params[:record]
    @os = @notification&.params&.dig(:os) || @notification&.params&.dig("os")
    @user_agent = @notification&.params&.dig(:user_agent) || @notification&.params&.dig("user_agent")
    @account_url = settings_connected_accounts_url

    return unless EmailRecipientThrottle.allow!(@recipient.email_address, kind: :sign_in_from_new_device)

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.sign_in_from_new_device.subject", os: @os)
    )
  end

  def password_locked
    @recipient = params[:recipient]
    @duration = User::LOCK_DURATION.inspect
    @sign_in_url = new_session_url

    return unless EmailRecipientThrottle.allow!(@recipient.email_address, kind: :password_locked)

    mail(to: @recipient.email_address, subject: t("notification_mailer.password_locked.subject"))
  end

  # Daily/weekly digest. Unlike the per-event mailers above, `digest` takes
  # positional args (user + array of notifications) because it's invoked
  # directly by `DigestMailerJob`, not through Noticed's `deliver_by :email`
  # parameterized pipeline. Subject reflects the user's chosen cadence;
  # template lays out notifications grouped by category.
  # Takes notification IDS, not records. Two reasons, both load-bearing:
  # serialising AR objects into deliver_later means one row deleted by
  # retention between enqueue and render raises DeserializationError and
  # dead-letters the entire digest; and re-querying here makes delivery time —
  # not selection time — the moment read state is judged. A user who reads an
  # item while the mail sits in the queue does not get emailed about it.
  # Every id having been read since selection means there is nothing to say,
  # so no mail goes out at all.
  def digest(user, notification_ids)
    @notifications = user.notifications
                         .where(id: notification_ids, read_at: nil)
                         .order(created_at: :desc)
                         .to_a
    return if @notifications.empty?

    @user = user
    @cadence = user.preferences&.notification_preferences_object&.digest_cadence || "daily"
    @app_name = t("application.name")
    @count = @notifications.size
    @preferences_url = edit_settings_notification_preferences_url

    mail(
      to: user.email_address,
      subject: t("notification_mailer.digest.subject.#{@cadence}", app_name: @app_name)
    )
  end
  private

  def abort_when_recipient_suspended
    self.response_body = "" if params[:recipient]&.suspended?
  end
end
