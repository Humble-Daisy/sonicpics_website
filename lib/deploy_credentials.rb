# Staging runs as production on its own credentials: /docs/developer/deployment (Credentials per deploy).
module DeployCredentials
  NAME = /\A[a-z][a-z0-9_]*\z/

  def self.paths(env = ENV, root: Rails.root)
    name = env["RAILS_CREDENTIALS_ENV"].to_s.strip
    return {} if name.empty?
    raise ArgumentError, "RAILS_CREDENTIALS_ENV must name credentials like `staging`, got #{name.inspect}" unless NAME.match?(name)

    { content_path: root.join("config/credentials/#{name}.yml.enc"), key_path: root.join("config/credentials/#{name}.key") }
  end

  def self.deployment(env = ENV)
    env["RAILS_CREDENTIALS_ENV"].to_s.strip.presence || Rails.env
  end
end
