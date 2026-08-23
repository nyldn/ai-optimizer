# frozen_string_literal: true

require "json"
require "rbconfig"

module AIOptimizer
  class CheckContext
    attr_reader :home, :data_dir, :workspace_root, :path, :runner, :platform,
                :architecture, :macos_version

    def initialize(home:, data_dir:, workspace_root:, path:, runner:,
                   platform:, architecture:, macos_version:)
      @home = File.expand_path(home)
      @data_dir = File.expand_path(data_dir)
      @workspace_root = File.expand_path(workspace_root)
      @path = path.to_s
      @runner = runner
      @platform = platform.to_s
      @architecture = architecture.to_s
      @macos_version = macos_version.to_s
    end

    def executable_paths(name)
      seen = {}
      path.split(File::PATH_SEPARATOR).each_with_object([]) do |directory, matches|
        next if directory.nil? || directory.empty?

        candidate = File.expand_path(File.join(directory, name))
        next unless File.file?(candidate) && File.executable?(candidate)

        identity = begin
          File.realpath(candidate)
        rescue Errno::ENOENT, Errno::EACCES
          candidate
        end
        next if seen[identity]

        seen[identity] = true
        matches << candidate
      end
    end
  end

  class SystemCheck
    def initialize(context)
      @context = context
    end

    def call
      supported_platform = @context.platform.downcase.include?("darwin")
      major = @context.macos_version.split(".").first.to_i
      supported_version = major >= 13
      status = supported_platform && supported_version ? "pass" : "fail"
      message = status == "pass" ? "macOS is supported" : "macOS 13 or later is required"
      [Finding.new(
        id: "system.macos", category: "system", status: status,
        message: message,
        detail: "macOS #{@context.macos_version}, #{@context.architecture}",
        remediation: status == "fail" ? "Run AI Environment Optimizer on macOS 13 or later." : nil,
        required: true, affects: ["ai-env-optimizer"]
      )]
    end

    def required?
      true
    end
  end

  class ToolsCheck
    TOOLS = {
      "claude" => "Claude Code",
      "codex" => "Codex",
      "graphify" => "Graphify"
    }.freeze

    def initialize(context)
      @context = context
    end

    def call
      TOOLS.map { |command, label| inspect_tool(command, label) } +
        [inspect_claude_mem, inspect_atk]
    end

    def required?
      false
    end

    private

    def inspect_tool(command, label)
      paths = @context.executable_paths(command)
      id_name = command.tr("-", "_")
      if paths.empty?
        return Finding.new(
          id: "tools.#{id_name}.present", category: "tools", status: "warn",
          message: "#{label} is not installed or not on PATH",
          remediation: remediation_for(command), required: false,
          affects: [command]
        )
      end

      result = @context.runner.run([paths.first, "--version"], timeout: 5)
      version = result.success? ? result.stdout.to_s.lines.first.to_s.strip : "version unavailable"
      duplicate_note = paths.length > 1 ? "; #{paths.length} PATH matches" : ""
      status = paths.length > 1 ? "warn" : "pass"
      Finding.new(
        id: "tools.#{id_name}.present", category: "tools", status: status,
        message: "#{label} is available",
        detail: Redactor.scrub("#{version}#{duplicate_note}", home: @context.home),
        remediation: paths.length > 1 ?
          "Ensure the preferred #{command} appears first; update or remove stale installations if needed." : nil,
        required: false, affects: [command]
      )
    end

    def remediation_for(command)
      case command
      when "claude"
        "Install Claude Code if you want Claude diagnostics."
      when "codex"
        "Install Codex if you want Codex diagnostics."
      else
        "Install #{command} only if you want this optional integration."
      end
    end

    def inspect_atk
      executable = !@context.executable_paths("atk").empty? ||
                   !@context.executable_paths("agentation").empty?
      launch_agent = File.file?(
        File.join(@context.home, "Library", "LaunchAgents", "com.agentation.mcp-server.plist")
      )
      if executable || launch_agent
        Finding.new(
          id: "tools.atk.present", category: "tools", status: "pass",
          message: "Agentation (ATK) is available",
          detail: "Detected through local integration metadata; endpoint values were not read.",
          required: false, affects: ["agentation"]
        )
      else
        Finding.new(
          id: "tools.atk.present", category: "tools", status: "warn",
          message: "Agentation (ATK) was not detected",
          remediation: "Install Agentation only if you want this optional integration.",
          required: false, affects: ["agentation"]
        )
      end
    end

    def inspect_claude_mem
      paths = @context.executable_paths("claude-mem")
      return inspect_tool("claude-mem", "Claude-Mem") unless paths.empty?

      plugin_roots = [
        File.join(@context.home, ".claude", "plugins", "cache", "*", "claude-mem"),
        File.join(@context.home, ".codex", "plugins", "cache", "*", "claude-mem")
      ]
      installed = plugin_roots.any? do |pattern|
        Dir.glob(pattern).any? { |candidate| File.directory?(candidate) }
      end
      if installed
        Finding.new(
          id: "tools.claude_mem.present", category: "tools", status: "pass",
          message: "Claude-Mem is available",
          detail: "Detected as a local plugin installation.",
          required: false, affects: ["claude-mem"]
        )
      else
        Finding.new(
          id: "tools.claude_mem.present", category: "tools", status: "warn",
          message: "Claude-Mem was not detected",
          remediation: "Install Claude-Mem only if you want this optional integration.",
          required: false, affects: ["claude-mem"]
        )
      end
    end
  end

  class MCPCheck
    def initialize(context)
      @context = context
    end

    def call
      claude_count, claude_error = claude_server_count
      codex_count, codex_error = codex_server_count
      [mcp_finding("claude", "Claude Code", claude_count, claude_error),
       mcp_finding("codex", "Codex", codex_count, codex_error)]
    end

    def required?
      false
    end

    private

    def claude_server_count
      paths = [File.join(@context.home, ".claude.json"), File.join(@context.home, ".claude", "settings.json")]
      count = 0
      paths.each do |path|
        next unless File.file?(path)
        raise ConfigError, "symlinked Claude configuration" if File.symlink?(path)

        count += count_mcp_hashes(JSON.parse(File.binread(path)))
      end
      [count, nil]
    rescue JSON::ParserError, ConfigError => error
      [0, error.class.name]
    end

    def count_mcp_hashes(value)
      case value
      when Hash
        direct = value["mcpServers"].is_a?(Hash) ? value["mcpServers"].length : 0
        direct + value.values.map { |child| count_mcp_hashes(child) }.inject(0, :+)
      when Array
        value.map { |child| count_mcp_hashes(child) }.inject(0, :+)
      else
        0
      end
    end

    def codex_server_count
      path = File.join(@context.home, ".codex", "config.toml")
      return [0, nil] unless File.file?(path)
      raise ConfigError, "symlinked Codex configuration" if File.symlink?(path)

      count = File.foreach(path).count do |line|
        line.match?(/^\s*\[mcp_servers\.(?:"[^"]+"|[A-Za-z0-9_.-]+)\]\s*$/)
      end
      [count, nil]
    rescue ArgumentError, ConfigError => error
      [0, error.class.name]
    end

    def mcp_finding(id_name, label, count, error)
      if error
        Finding.new(
          id: "mcp.#{id_name}.parse", category: "mcp", status: "warn",
          message: "#{label} MCP configuration could not be parsed",
          detail: "Configuration is present but invalid or unsafe to follow.",
          remediation: "Validate the #{label} configuration with its native doctor.",
          required: false, affects: [id_name]
        )
      else
        noun = count == 1 ? "server" : "servers"
        Finding.new(
          id: "mcp.#{id_name}.configured", category: "mcp", status: "info",
          message: "#{label} MCP inventory inspected",
          detail: "#{count} configured #{noun}; endpoint values were not read into the report.",
          required: false, affects: [id_name]
        )
      end
    end
  end

  class SkillsCheck
    def initialize(context)
      @context = context
    end

    def call
      roots = [
        File.join(@context.home, ".claude", "skills"),
        File.join(@context.home, ".codex", "skills"),
        File.join(@context.home, ".agents", "skills")
      ]
      names = []
      invalid = 0
      unavailable_links = 0
      roots.each do |root|
        next unless Dir.exist?(root)

        Dir.children(root).sort.each do |name|
          candidate = File.join(root, name)
          if unavailable_link?(candidate)
            unavailable_links += 1
            next
          end

          skill_file = File.join(candidate, "SKILL.md")
          next unless File.file?(skill_file)

          names << name
          invalid += 1 unless valid_frontmatter?(skill_file)
        end
      end
      duplicates = names.group_by { |name| name }.count { |_name, matches| matches.length > 1 }
      status = if invalid.positive?
                 "warn"
               elsif duplicates.positive?
                 "info"
               else
                 "pass"
               end
      findings = [Finding.new(
        id: "skills.inventory", category: "skills", status: status,
        message: "Skill inventory inspected",
        detail: "#{names.length} skills, #{duplicates} names shared across tool roots, " \
          "#{invalid} invalid frontmatter files",
        remediation: invalid.positive? ? "Fix invalid SKILL.md frontmatter before using those skills." : nil,
        required: false, affects: ["claude", "codex"]
      )]
      if unavailable_links.positive?
        noun = unavailable_links == 1 ? "directory" : "directories"
        findings << Finding.new(
          id: "skills.linked_candidates", category: "skills", status: "warn",
          message: "Some linked skill directories are unavailable",
          detail: "#{unavailable_links} linked skill #{noun} could not be used; paths were omitted.",
          remediation: "Repair or remove broken skill links, then rerun ai-env-optimizer doctor.",
          required: false, affects: ["claude", "codex"]
        )
      end
      findings
    end

    def required?
      false
    end

    private

    def unavailable_link?(path)
      return false unless File.symlink?(path)

      !File.directory?(File.realpath(path))
    rescue SystemCallError
      true
    end

    def valid_frontmatter?(path)
      content = File.binread(path, 16_384)
      return false unless content.start_with?("---\n")

      closing = content.index("\n---\n", 4)
      return false unless closing

      header = content[4...closing]
      header.match?(/^name:\s*\S+/) && header.match?(/^description:\s*\S+/)
    rescue Errno::EACCES, Errno::ENOENT
      false
    end
  end

  class ProductCheck
    def initialize(context)
      @context = context
    end

    def call
      config = Config.new(data_dir: @context.data_dir, default_workspace_root: @context.workspace_root)
      if File.file?(config.path)
        config.load
        [Finding.new(
          id: "product.config", category: "product", status: "pass",
          message: "AI Environment Optimizer configuration is valid", required: true,
          affects: ["ai-env-optimizer"]
        )]
      else
        [Finding.new(
          id: "product.config", category: "product", status: "info",
          message: "AI Environment Optimizer has not been set up yet",
          remediation: "Run ai-env-optimizer setup when you want to save defaults.",
          required: false, affects: ["ai-env-optimizer"]
        )]
      end
    rescue ConfigError, OwnershipError
      [Finding.new(
        id: "product.config", category: "product", status: "fail",
        message: "AI Environment Optimizer configuration is invalid",
        remediation: "Move the invalid file aside, then run ai-env-optimizer setup.",
        required: true, affects: ["ai-env-optimizer"]
      )]
    end

    def required?
      true
    end
  end

  class WorkspaceCheck
    def initialize(context)
      @context = context
    end

    def call
      unless Dir.exist?(@context.workspace_root)
        return [Finding.new(
          id: "workspaces.inventory", category: "workspaces", status: "warn",
          message: "Workspace root does not exist",
          remediation: "Run setup with an existing --workspace-root.", required: false
        )]
      end

      repos = Dir.children(@context.workspace_root).sort.each_with_object([]) do |entry, matches|
        candidate = File.join(@context.workspace_root, entry)
        next unless File.directory?(candidate)
        next unless File.exist?(File.join(candidate, ".git"))

        matches << candidate
      end
      instructions = repos.count do |repo|
        File.file?(File.join(repo, "AGENTS.md")) || File.file?(File.join(repo, "CLAUDE.md"))
      end
      dirty = repos.count do |repo|
        result = @context.runner.run(["/usr/bin/git", "-C", repo, "status", "--porcelain", "--untracked-files=no"], timeout: 8)
        result.success? && !result.stdout.to_s.empty?
      end
      noun = repos.length == 1 ? "workspace" : "workspaces"
      [Finding.new(
        id: "workspaces.inventory", category: "workspaces", status: "info",
        message: "Workspace inventory inspected",
        detail: "#{repos.length} Git #{noun}; #{instructions} with agent instructions; #{dirty} with tracked changes",
        required: false, affects: ["workspaces"]
      )]
    rescue Errno::EACCES
      [Finding.new(
        id: "workspaces.inventory", category: "workspaces", status: "unknown",
        message: "Workspace root is not readable", required: false
      )]
    end

    def required?
      false
    end
  end
end
