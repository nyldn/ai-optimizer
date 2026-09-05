# frozen_string_literal: true

require "json"

module AIOptimizer
  class DesktopApplications
    APPS = {
      "claude" => { names: %w[Claude], identifier: "com.anthropic.claudefordesktop", label: "Claude Desktop" },
      "codex" => { names: %w[Codex ChatGPT], identifier: "com.openai.codex", label: "Codex desktop / ChatGPT" }
    }.freeze

    def initialize(context)
      @context = context
      @inventory = {}
    end

    def installed?(provider)
      !inventory(provider).fetch(:versions).empty?
    end

    def inventory(provider)
      @inventory[provider] ||= inspect_app(APPS.fetch(provider))
    end

    private

    def inspect_app(app)
      versions = []
      unknown = 0
      seen = {}
      @context.application_roots.each do |directory|
        app.fetch(:names).each do |name|
          candidate = File.join(directory, "#{name}.app")
          next unless File.exist?(candidate) || File.symlink?(candidate)

          begin
            root = File.realpath(candidate)
            next if seen[root]

            seen[root] = true
            plist = File.join(root, "Contents", "Info.plist")
            raise ConfigError unless File.file?(plist) && !File.symlink?(plist)
            raise ConfigError unless File.realpath(plist).start_with?(root + File::SEPARATOR)
            raise ConfigError if File.size(plist) > 1_048_576

            identifier = metadata_value(plist, "CFBundleIdentifier")
            next if name == "ChatGPT" && identifier == "com.openai.chat"

            raise ConfigError unless identifier == app.fetch(:identifier)

            executable = metadata_value(plist, "CFBundleExecutable")
            raise ConfigError unless executable.match?(/\A[A-Za-z0-9_. -]+\z/)

            binary = File.join(root, "Contents", "MacOS", executable)
            raise ConfigError unless File.file?(binary) && File.executable?(binary)
            raise ConfigError unless File.realpath(binary).start_with?(root + File::SEPARATOR)

            version = metadata_value(plist, "CFBundleShortVersionString")
            versions << (version.match?(/\A[0-9]+(?:\.[0-9]+){0,5}\z/) && version.length <= 64 ? version : "unavailable")
          rescue SystemCallError, ConfigError, JSON::ParserError, TypeError
            unknown += 1
          end
        end
      end
      {versions: versions, unknown: unknown}
    end

    def metadata_value(plist, key)
      result = @context.runner.run(["/usr/bin/plutil", "-extract", key, "raw", "-o", "-", plist], timeout: 3)
      raise ConfigError unless result.success?

      result.stdout.to_s.strip
    end
  end

  class DesktopCheck
    CLAUDE_DOC = "https://code.claude.com/docs/en/desktop"
    CODEX_DOC = "https://learn.chatgpt.com/docs/extend/mcp"

    def initialize(context)
      @context = context
    end

    def required?
      false
    end

    def call
      findings = DesktopApplications::APPS.flat_map do |provider, app|
        inventory = @context.desktop_applications.inventory(provider)
        versions = inventory.fetch(:versions)
        unknown = inventory.fetch(:unknown)
        status = if versions.empty?
                   unknown.positive? ? "unknown" : "info"
                 elsif versions.length > 1 || unknown.positive?
                   "warn"
                 else
                   "pass"
                 end
        rows = [Finding.new(
          id: "desktop.#{provider}.present", category: "desktop", status: status,
          message: versions.empty? ? "#{app.fetch(:label)} was not verified in standard application folders" : "#{app.fetch(:label)} application bundle detected",
          detail: "#{versions.length} distinct verified bundles; versions: #{versions.empty? ? 'none' : versions.join(', ')}; " \
            "#{unknown} unverified candidates. Bundle metadata does not establish login, running state, plan access, or signature trust.",
          remediation: %w[warn unknown].include?(status) ? "Inspect the preferred app in Finder and its About dialog; resolve extra or unverified copies only after checking their use." : nil,
          required: false, affects: [provider], links: [provider == "claude" ? CLAUDE_DOC : CODEX_DOC]
        )]
        rows << capability_finding(provider) unless versions.empty?
        rows
      end
      findings << desktop_mcp
      findings
    end

    private

    def capability_finding(provider)
      detail = if provider == "claude"
                 "Local Code sessions can use Claude Code settings, skills, hooks, and project memory. " \
                   "Chat, Cowork, local Code, and cloud Code have different execution and configuration boundaries. " \
                   "Headless claude --print scripting and coordinated agent teams require the CLI; desktop has its own scheduled tasks. " \
                   "Check mode, login, connectors, and permissions in the app; CLI authentication is not desktop readiness evidence."
               else
                 "Desktop and CLI share MCP configuration for the same Codex host; desktop offers an MCP settings UI. " \
                   "Shell scripts and CI using codex exec require a supported CLI entry point on PATH. " \
                   "App-bundled runtimes are not treated as standalone CLI installations. " \
                   "Check the selected host, login, enabled tools, and permissions in the app; local files do not prove cloud configuration."
               end
      Finding.new(
        id: "desktop.#{provider}.capabilities", category: "desktop", status: "info",
        message: "#{provider == 'claude' ? 'Claude' : 'Codex'} desktop and CLI capabilities differ",
        detail: detail, required: false, affects: [provider],
        links: provider == "claude" ? [CLAUDE_DOC] : [CODEX_DOC, "https://learn.chatgpt.com/docs/non-interactive-mode"]
      )
    end

    def desktop_mcp
      relative = ["Library", "Application Support", "Claude", "claude_desktop_config.json"]
      path = @context.home
      relative.each do |part|
        path = File.join(path, part)
        raise ConfigError if File.symlink?(path)
      end
      unless File.exist?(path)
        return Finding.new(
          id: "mcp.claude_desktop.configured", category: "mcp", status: "info",
          message: "No manual Claude Desktop MCP configuration was found",
          detail: "Desktop extensions and remote connectors may still be configured in the app; their state is not inspected.",
          required: false, affects: ["claude"], links: [CLAUDE_DOC]
        )
      end
      raise ConfigError unless File.file?(path) && File.size(path) <= 1_048_576

      document = JSON.parse(File.binread(path))
      raise ConfigError unless document.is_a?(Hash)
      servers = document.fetch("mcpServers", {})
      raise ConfigError unless servers.is_a?(Hash) && servers.values.all? { |server| server.is_a?(Hash) }

      Finding.new(
        id: "mcp.claude_desktop.configured", category: "mcp", status: "info",
        message: "Manual Claude Desktop MCP inventory inspected",
        detail: "#{servers.length} configured servers; inventory only, not connection health. " \
          "Current desktop versions also load these definitions into local Code sessions. " \
          "The standalone CLI does not read this file directly. Extensions and remote connectors are not counted.",
        required: false, affects: ["claude"], links: [CLAUDE_DOC]
      )
    rescue SystemCallError, ConfigError, JSON::ParserError, TypeError
      Finding.new(
        id: "mcp.claude_desktop.parse", category: "mcp", status: "warn",
        message: "Manual Claude Desktop MCP configuration could not be inspected",
        detail: "The file is invalid, too large, unreadable, or unsafe to follow; configuration contents were omitted.",
        remediation: "Inspect Claude Desktop Settings and validate its manual MCP configuration locally. Do not paste credentials into reports.",
        required: false, affects: ["claude"], links: [CLAUDE_DOC]
      )
    end
  end
end
