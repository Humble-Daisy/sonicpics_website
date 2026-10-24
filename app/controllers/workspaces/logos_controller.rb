module Workspaces
  # The logo picker hub, lazy-loaded into the Profile page's modal, and logo
  # removal. Saves post to workspaces#update, where the logo lives.
  class LogosController < ApplicationController
    include WorkspaceScoped

    rate_limit to: 20, within: 3.minutes, only: :destroy,
      by: -> { Current.user&.id || request.remote_ip },
      with: -> {
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: error_toast(t("workspaces.update.rate_limited")),
                   status: :too_many_requests
          end
          format.html { redirect_to edit_workspace_path(@workspace), alert: t("workspaces.update.rate_limited") }
        end
      }

    def show
      authorize @workspace, policy_class: Workspaces::LogoPolicy
      identity = @workspace.identity

      render partial: "shared/identity_picker_hub",
        locals: {
          identity: identity,
          model: @workspace,
          form_url: workspace_path(@workspace),
          hub_url: workspace_logo_path(@workspace),
          current_source: identity.resolve_source(params[:source])
        },
        layout: false
    end

    def destroy
      authorize @workspace, policy_class: Workspaces::LogoPolicy
      result = @workspace.identity.apply(source: "initials")

      if result.success?
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to edit_workspace_path(@workspace), notice: t(".success") }
        end
      else
        respond_to do |format|
          format.turbo_stream { render turbo_stream: error_toast(result.error_message), status: :unprocessable_content }
          format.html { redirect_to edit_workspace_path(@workspace), alert: result.error_message }
        end
      end
    end
  end
end
