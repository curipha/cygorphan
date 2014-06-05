#!/usr/bin/ruby
require 'cgi/util'
require 'optparse'

pkg   = {}  # Required package list for each package : { 'package' => [ 'required_pkg', ...] }
pkg_d = {}  # Package short description              : { 'package' => 'description', ...}

i_pkg = []  # Packages installed                : [ 'package', ...]
r_pkg = []  # Packages required by the other    : [ 'required_pkg', ...]
b_pkg = []  # Packages marked as "Base"         : [ 'package', ...]
o_pkg = []  # Packages marked as "Obsolete"     : [ 'package', ...]
p_pkg = []  # Packages marked as "Post install" : [ 'package', ...]

SETUPINI = 'C:\cygwin\_package\http%3a%2f%2fftp.jaist.ac.jp%2fpub%2fcygwin%2f\x86\setup.ini'  # Fallback setup.ini
SETUPRC  = '/etc/setup/setup.rc'

OPTS = {}
OptionParser.new do |op|
  op.version = '0.1.0'

  op.on('-b', '--display-base-packages',
        'Display packages even if its category is "Base".') {|f| OPTS[:base] = f }
  op.on('-o', '--display-obsolete-packages',
        'Also display packages marked as "Obsolete" regardless of orphaned.') {|f| OPTS[:obsl] = f }
  op.on('-s', '--simple',
        'Display as simple output format.') {|f| OPTS[:smpl] = f }


  OPTS[:mode] = 'orphaned'

  op.on('-d PACKAGE', '--depended-on=PACKAGE',
        'Display packages depended on the PACKAGE.') {|v|
    OPTS[:mode] = 'depended'
    OPTS[:depended] = v
  }
  op.on('-r PACKAGE', '--required-by=PACKAGE',
        'Display packages required by the PACKAGE.') {|v|
    OPTS[:mode] = 'required'
    OPTS[:required] = v
  }

  op.parse(ARGV)
end

abort 'Error: "Required" and "Depended" option can not be specified at the same time.' \
  unless OPTS[:depended].nil? || OPTS[:required].nil?


def sputs(str)
  puts str unless OPTS[:smpl]
end
def prettify(pkg, dscr = '')
  return pkg if OPTS[:smpl]

  r  = "* #{pkg}"
  r += " : #{dscr}" unless dscr.empty?

  return r
end
def findini
  return false unless File.readable?(SETUPRC) # setup.rc is not exist or not readable

  cachedir = '' # Cache directory of Cygwin installer
  lastmirr = '' # URI of last used mirror
  downdir  = '' # Last-used download directory

  open(SETUPRC) do |fp|
    while l = fp.gets
      case l
      when /^last-cache/
        cachedir = fp.gets.strip
      when /^last-mirror/
        lastmirr = fp.gets.strip
      end

      unless cachedir.empty? || lastmirr.empty?
        downdir = cachedir + '\\' + CGI.escape(lastmirr)
        break
      end
    end
  end

  return false if     downdir.empty?          # Failed to parse setup.rc
  return false unless File.readable?(downdir) # Last-used download directory is not readable


  dir = Dir.entries(downdir).delete_if {|d| d == '.' || d == '..' }

  return false if     dir.length != 1         # Last-used mirror directory is empty or has more than one directory
  return false unless dir[0] =~ /^x86(_64)?$/ # There is no such directory of x86 or x86_64

  return "#{downdir}\\#{dir[0]}\\setup.ini"
end


setupini = findini || SETUPINI
abort "Error: setup.ini is not readable!! #{setupini}" unless File.readable?(setupini)

open(setupini) do |fp|
  cur= ''

  while l = fp.gets
    case l
    when /^@/
      cur = l.gsub(/^@\s+/, '').strip
      pkg[cur] = []
    when /^requires:/
      pkg[cur] = l.gsub(/^requires:\s/, '').split(' ').map {|v| v.strip }
    when /^sdesc:/
      pkg_d[cur] = l.gsub(/^sdesc:\s*"([^"]+)"/, '\1').gsub(/\\(.)/, '\1').strip
    when /^category:.*\sBase/
      b_pkg << cur
    when /^category:.*\s_obsolete/
      o_pkg << cur
    when /^category:.*\s_PostInstallLast/
      p_pkg << cur
    end
  end
end


case OPTS[:mode]
# Find orphaned packages
when 'orphaned'
  # cygcheck belongs to "cygwin" package, tail and cut belong to "coreutils" package
  `cygcheck -cd | tail -n +3 | cut -d' ' -f1`.lines do |l|
    l.strip!

    if pkg[l].nil?
      $stderr.puts "Warning: Package #{l} is marked as installed, but it is not listed in setup.ini."
    else
      r_pkg << pkg[l]
      i_pkg << l
    end
  end

  r_pkg = r_pkg.flatten.uniq
  orp   = i_pkg.sort

  orp -= r_pkg # Delete packages required by the other
  orp -= p_pkg # Delete packages marked as "Post install"

  # Delete packages whose category is "Base"
  orp -= b_pkg unless OPTS[:base]


  if OPTS[:obsl]
    buf = []
    o_pkg.each {|v| buf << prettify(v) if i_pkg.include?(v) }

    unless buf.length < 1
      sputs 'Obsoleted package(s)'
      puts buf.sort
    end
  end

  sputs 'Orphaned package(s)'

  if orp.length < 1
    sputs 'None.'
  else
    lj = orp.map {|v| v.length }.max

    orp.each {|v| puts prettify(v.ljust(lj), pkg_d[v]) }
  end

# Find depended on packages
when 'depended'
  deps = pkg[OPTS[:depended]]

  if deps.nil?
    puts 'No such package exists.'
  elsif deps.length < 1
    puts 'None.'
  else
    puts deps.sort
  end

# Find required by packages
when 'required'
  if pkg[OPTS[:required]].nil?
    puts 'No such package exists.'
  else
    reqs = []
    pkg.each {|k, v| reqs << k if v.include?(OPTS[:required]) }

    puts reqs.length < 1 ? 'None.' : reqs.sort
  end
end

