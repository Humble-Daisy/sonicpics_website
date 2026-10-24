module Workspaces
  # The logo picker hub is part of editing the workspace's identity, so it
  # carries ProfilePolicy's capability (manage_settings), not a narrower one.
  class LogoPolicy < ApplicationPolicy
    def show?
      can?("manage_settings")
    end

    def destroy?
      can?("manage_settings")
    end
  end
end
