require 'formula_installer'
require 'hardware'
require 'blacklist'

module Homebrew extend self
  def install
    raise FormulaUnspecifiedError if ARGV.named.empty?

    if ARGV.include? '--head'
      raise "Specify `--HEAD` in uppercase to build from trunk."
    end

    ARGV.named.each do |name|
      # if a formula has been tapped ignore the blacklisting
      if not File.file? HOMEBREW_REPOSITORY/"Library/Formula/#{name}.rb"
        msg = blacklisted? name
        raise "No available formula for #{name}\n#{msg}" if msg
      end
    end unless ARGV.force?

    if Process.uid.zero? and not File.stat(HOMEBREW_BREW_FILE).uid.zero?
      raise "Cowardly refusing to `sudo brew install'\n#{SUDO_BAD_ERRMSG}"
    end

    install_formulae ARGV.formulae
  end

  def check_ppc
    case Hardware.cpu_type when :ppc, :dunno
      abort <<-EOS.undent
        Sorry, Homebrew does not support your computer's CPU architecture.
        For PPC support, see: https://github.com/mistydemeo/tigerbrew
        EOS
    end
  end

  def check_writable_install_location
    raise "Cannot write to #{HOMEBREW_CELLAR}" if HOMEBREW_CELLAR.exist? and not HOMEBREW_CELLAR.writable_real?
    raise "Cannot write to #{HOMEBREW_PREFIX}" unless HOMEBREW_PREFIX.writable_real? or HOMEBREW_PREFIX.to_s == '/usr/local'
  end

  def check_xcode
    require 'cmd/doctor'
    checks = Checks.new
    %w{check_for_latest_xcode check_xcode_license_approved}.each do |check|
      out = checks.send(check)
      opoo out unless out.nil?
    end
  end

  def check_macports
    unless MacOS.macports_or_fink.empty?
      opoo "It appears you have MacPorts or Fink installed."
      puts "Software installed with other package managers causes known problems for"
      puts "Homebrew. If a formula fails to build, uninstall MacPorts/Fink and try again."
    end
  end

  def check_cellar
    FileUtils.mkdir_p HOMEBREW_CELLAR if not File.exist? HOMEBREW_CELLAR
  rescue
    raise <<-EOS.undent
      Could not create #{HOMEBREW_CELLAR}
      Check you have permission to write to #{HOMEBREW_CELLAR.parent}
    EOS
  end

  def perform_preinstall_checks
    check_ppc
    check_writable_install_location
    check_xcode
    check_macports
    check_cellar
  end

  def install_formulae formulae
    formulae = [formulae].flatten.compact
    unless formulae.empty?
      perform_preinstall_checks
      formulae.each do |f|
        install_formula(f)
      end
    end
  end

  def install_formula f
    fi = FormulaInstaller.new(f)
    fi.install
    fi.caveats
    fi.finish
  rescue FormulaInstallationAlreadyAttemptedError
    # We already attempted to install f as part of the dependency tree of
    # another formula. In that case, don't generate an error, just move on.
  rescue CannotInstallFormulaError => e
    ofail e.message
  end
end
