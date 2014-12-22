#!/usr/bin/env ruby
require 'cgi/util'
require 'optparse'

class Cygorphan
  # Constants
  SETUPRC   = '/etc/setup/setup.rc'
  INSTALLDB = '/etc/setup/installed.db'

  # Accessors
  attr_accessor :include_base, :include_obsolete, :simple_output

  # Constructor
  def initialize
    # Initialize instance variables
    @pkg   = {}  # Required package list for each package : { 'package' => [ 'required_pkg', ...] }
    @pkg_d = {}  # Package short description              : { 'package' => 'description', ...}

    @b_pkg = []  # Packages marked as "Base"         : [ 'package', ...]
    @o_pkg = []  # Packages marked as "Obsolete"     : [ 'package', ...]
    @p_pkg = []  # Packages marked as "Post install" : [ 'package', ...]

    @i_pkg = []  # Packages installed             : [ 'package', ...]
    @r_pkg = []  # Packages required by the other : [ 'required_pkg', ...]

    # Settings
    @include_base     = false # true: Display packages whose category is "Base"
    @include_obsolete = false # true: Display packages whose category is "Obsolete"
    @simple_output    = false # true: Display as simple output format


    # Parse setup.ini and set up package information
    setpkg
  end

  # Find orphaned packages
  def orphaned
    setpkg2 # Set up installed package information

    if @include_obsolete
      sputs 'Obsoleted package(s)'
      putpkg(@o_pkg & @i_pkg)
    end

    orp = @i_pkg - @r_pkg # Delete packages required by the other

    sputs 'Orphaned package(s)'
    putpkg(orp)
  end

  # Find depended on packages
  def depended(pkg)
    abort 'No such package exists.' unless @pkg.key?(pkg)
    warn 'Warning: A option to display obsolete package is available only for finding orphan.' if @include_obsolete

    sputs "Package(s) depended on #{pkg}"
    putpkg(getdeps(pkg))
  end

  # Find required by packages
  def required(pkg)
    abort 'No such package exists.' unless @pkg.key?(pkg)
    warn 'Warning: A option to display obsolete package is available only for finding orphan.' if @include_obsolete

    sputs "Package(s) required by #{pkg}"
    putpkg(@pkg[pkg])
  end


  private

  # Display strings if 'simple' option is not set
  def sputs(str)
    puts str unless @simple_output
  end

  # Display package information
  def putpkg(pkg)
    pkg = [*pkg]

    pkg -= @b_pkg unless @include_base  # Delete packages whose category is "Base"
    pkg -= @p_pkg                       # Delete packages marked as "Post install"

    if pkg.empty?
      sputs 'None.'
    else
      pkg.sort!

      if @simple_output
        puts pkg
      else
        lmax = pkg.map {|v| v.length }.max

        pkg.each {|v|
          r  = "* #{v.ljust(lmax)}"
          r += " : #{@pkg_d[v]}" unless @pkg_d[v].nil? || @pkg_d[v].empty?
          puts r
        }
      end
    end
  end

  # Get the path of setup.ini
  def findini
    return false unless File.readable?(SETUPRC) # setup.rc is not exist or not readable

    cachedir = '' # Cache directory of Cygwin installer
    lastmirr = '' # URI of last used mirror
    downdir  = '' # Last-used download directory

    File.open(SETUPRC, File::RDONLY) do |fp|
      fp.flock(File::LOCK_SH)

      while l = fp.gets
        case l
        when /^last-cache/
          cachedir = fp.gets.strip
        when /^last-mirror/
          lastmirr = fp.gets.strip
        else
          next
        end

        unless cachedir.empty? || lastmirr.empty?
          downdir = cachedir + '\\' + CGI.escape(lastmirr)
          return false unless File.readable?(downdir)

          Dir.entries(downdir).each {|d|
            return "#{downdir}\\#{d}\\setup.ini" if d =~ /^x86(_64)?$/
          }
        end
      end
    end

    return false
  end

  # Parse setup.ini and set up package information
  def setpkg
    setupini = findini
    abort 'Error: Failed to find a path to setup.ini.'     unless setupini.is_a?(String)
    abort "Error: setup.ini is not readable!! #{setupini}" unless File.readable?(setupini)

    File.open(setupini, File::RDONLY) do |fp|
      cur = ''

      fp.flock(File::LOCK_SH)
      while l = fp.gets
        case l
        when /^@/
          cur = l.sub(/^@\s*/, '').strip
          @pkg[cur] = []
        when /^requires:/
          @pkg[cur] = l.sub(/^requires:\s*/, '').split(' ').map {|v| v.strip }
        when /^sdesc:/
          @pkg_d[cur] = l.sub(/^sdesc:\s*"([^"]+)"/, '\1').gsub(/\\(.)/, '\1').strip
        when /^category:/
          @b_pkg << cur if l =~ /\bBase\b/
          @o_pkg << cur if l =~ /\b_obsolete\b/
          @p_pkg << cur if l =~ /\b_PostInstallLast\b/
        end
      end
    end
  end

  # Parse installed.db and set up package information
  def setpkg2
    abort "Error: installed.db is not readable!! #{INSTALLDB}" unless File.readable?(INSTALLDB)

    r_pkg = []

    File.open(INSTALLDB, File::RDONLY) do |fp|
      fp.flock(File::LOCK_SH)

      fp.gets # skip 1st line
      while l = fp.gets
        l = l.split(' ', 2)[0].strip

        if @pkg[l].nil?
          warn "Warning: Package #{l} is marked as installed, but it is not listed in setup.ini."
        else
          r_pkg << @pkg[l]
          @i_pkg << l
        end
      end
    end

    @r_pkg = r_pkg.flatten
  end

  # Get package(s) depended on given package
  def getdeps(pkg)
    deps = []
    @pkg.each {|k, v| deps << k if v.include?(pkg) }

    return deps
  end
end


c = Cygorphan.new

mode = :orphaned # orphaned / depended / required

depended_package = nil  # Arguments (package name) of -d option
required_package = nil  # Arguments (package name) of -r option

OptionParser.new do |op|
  op.version = '0.1.3'

  op.on('-b', '--display-base-packages',
        'Display packages even if its category is "Base".') {|f| c.include_base = f }
  op.on('-o', '--display-obsolete-packages',
        'Also display packages marked as "Obsolete" regardless of orphaned.') {|f| c.include_obsolete = f }
  op.on('-s', '--simple',
        'Display as simple output format.') {|f| c.simple_output = f }

  op.on('-d PACKAGE', '--depended-on=PACKAGE',
        'Display packages depended on the PACKAGE.') {|v|
    mode = :depended
    depended_package = v
  }
  op.on('-r PACKAGE', '--required-by=PACKAGE',
        'Display packages required by the PACKAGE.') {|v|
    mode = :required
    required_package = v
  }

  op.parse(ARGV)
end

abort 'Error: -d and -r option can not be specified at the same time.' \
  unless depended_package.nil? || required_package.nil?

case mode
when :orphaned
  c.orphaned
when :depended
  c.depended(depended_package)
when :required
  c.required(required_package)
end

