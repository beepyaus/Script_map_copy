#!/usr/bin/env ruby

####
#TODO: bug; if the parent folder doesnt exist then higher up calls fail. 
#   /etc/ ...no httpd
#   calling /etc/httpd/vhosts 
#   needed mkdir for httpd and vhosts 

#############################################################################################################
# part 1. 
#   - should of copied (unix cp) the base and specific base_variant dir into the /tmp swap dir
#   - re-created the failsafe default http website pages 
#   - NO chown should of be done yet as Vagrant ( or Docker ) 
#     does not have permission to chown the 'troy' user owned files 
#
# part 2 - this file (ruby/perl/rust version
#   - chown and chmod the swap/temp dir to correct ACLs etc 
#   - use the XML spec file for lookup , normally
#     on dev machine: ~/Development/Jobi/Utils/sync/assets/config/tree_definitions/spec_foo.xml
#     on live machine: ~/sync/assets/config/tree_definitions/spec_foo.xml
      
#   - refer to the file-system file area normally 
#     on dev machine:  ~/Development/Jobi/Utils/sync/assets/config/base_{PROD,OTHER_TAG}
#     on live machine:  ~/sync/assets/config/base_{PROD,OTHER_TAG}
#   - cross-reference the spec xml file with the file-system space. 
#   - ANY directory not listed in the XML spec file cannot be copied over to the target machine. 
#   - rsync the files across. 
#   - simple_copy: is for straight forward folders, where the XML spec is too much work 
#   - map_copy: uses the XML spec and it the main point of this project. 

#   - NOTE: to be run on PROD/AWS EC2 or Vagrant and not really for the Dev Machine!!
#     Hence the TEST_PREFIX const! 

#   - perform rsync or similar on all the required dirs/files into the target (normally LIVE/PROD) server!!!

#   TODO: 
#        - handle rsync stdout response 
#        - OO ? wrap in a class? 
###############################################################################################################

#----------------Gems--------------------------
#...this doesnt work
#install_gem_or_fail("xmlsimple")
#install_gem_or_fail("etc")

require "xmlsimple"
require "etc" 
#----------------------------------------------

def install_gem_or_fail(gem_name) # {{{
    if gem_installed?(gem_name) == false then 
        puts "#{gem_name} gem is required!"
        exit 1
    else 
        require gem_name
    end
end# }}}

def gem_installed?(gem_name)# {{{
    begin
        found_gem = Gem::Specification.find_by_name(gem_name)
        found_gem = Gem::Specification.find_by_path 
        return found_gem
    rescue Gem::LoadError
        return false
    end
end # }}}


#
#Terminal colors 
#Foreground Code	Background Code
#  Black
#  	30	40
#  Red
#  	31	41
#  Green
#  	32	42
#  Yellow
#  	33	43
#  Blue
#  	34	44
#  Magenta
#  	35	45
#  Cyan
#  	36	46
#  White
#  	37	47
#  Black
#  	30	40
#  Red
#  	31	41
#  Green
#  	32	42
#  Yellow
#  	33	43
#  Blue
#  	34	44
#  Magenta
#  	35	45
#  Cyan
#  	36	46
#  White
#  	37	47
#  

def debug(_params, bold_me=false)# {{{
    yellow="33"
    bold = bold_me ? "1" : "" 
    if _get_debug() >= 2 then 
        puts "\033[#{bold};#{yellow}mDEBUG: #{_params}  \033[0m"
    end
end# }}}

def error(_params, bold_me=false) # {{{
    red="31"
    bold = bold_me ? "1" : "" 
    if _get_debug() >= 1 then 
        puts "\033[#{bold};#{red}mERROR: #{_params}  \033[0m"
    end
end # }}}

def info(_params, bold_me=false) # {{{
    blue="34" 
    bold = bold_me ? "1" : "" 
    if _get_debug() >= 3 then 
        puts "\033[#{bold};#{blue}mINFO: #{_params}  \033[0m"
    end
end # }}}

def splash(version)# {{{
puts <<HERE

       &&& &&  & &&
      && &\/&\|& ()|/ @, &&
      &\/(/&/&||/& /_/)_&/_&
   &() &\/&|()|/&\/ '%" & ()
  &_\_&&_\ |& |&&/&__%_/_& &&
&&   && & &| &| /& & % ()& /&&
 ()&_---()&\&\|&&-&&--%---()~
     &&     \|||
             |||               mapcopy.rb XML Tree Spec File copier. 
             |||               for Ruby Version 3.x
             |||               Version: #{version}
       , -=-~  .-^- _ 

HERE
end# }}}

def show_version()# {{{
    puts "Version #{$VERSION}"
end # }}}

def show_help()# {{{
    puts <<ZZZ

SYNOPSIS
    mapcopy.rb OPTIONS 

DESCRIPTION
    copies via rsync calls all of the listed /etc, config, other files 
    with their proper file mode (mode/user/group) to the target dirs referenced 
    in the XML Tree Specification files. 
    
    OPTIONS
        -h, --help 
        show this help area. 

        -d, --dry-run 
        prefix the critical rm -rf, rsync calls with either "echo " or use their own dry-run flag 
        to avoid doing a real operation that will delete or move or change files etc. 

        -m, --mode {LIVE|DEV|TEST} ...or other 
        tell the script what to do in certain events/operations. 
        currently not actually in use -only originally the dry-run option was flagged when NOT 'live' 

        -f, --force-yes 
        when stdin is asking for a y/n question force a 'y' to continue without user interaction

        -l, --log-level {debug|error|info}
        output extra debug 'puts' lines when needed ...like Rust's logging. 

        -b, --bypass-null 
        allow a target prefix of 'NULL', normally meaning it was the Development machine 
        Warning: allowed to run on a live production machine, would copy over Development settings 
        to the live working directories!

        Last Edited: Mon 07 Nov 2022 20:50:15

ZZZ

end# }}}

def get_log_level(level)# {{{
    debug = nil 
    case level 
        when "error" then 
            debug = 1
        when "debug" then 
            debug = 2
        when "info" then 
            debug = 3 
        else 
            debug = 0 
    end
    return debug
end# }}}

def set_args()# {{{
# when terminate < 0 the handler NEEDS to kill this process!!!!!
# - shift will pop first element and move the whole array to the left. 
    args = $* 

    #return set 
    terminate = false
    dry_run = false 
    force_yes = false 
    run_mode = "" 
    bypass_target_null = false 
    debug = -1

    while args.length > 0 do
        arg = args[0] 
        puts "arg: '" + arg + "'"
        case arg 
          when "--dry-run", "-d" then 
              dry_run = true
          when "--force-yes","-f" then 
              force_yes = true
          when "--mode","-m" then 
              run_mode = args[1] 
          when "--help","-h" then 
              show_help() 
              terminate = true
          when "--version", "-v" then 
              show_version()
              terminate = true
          when "--log-level", "-l" then 
              debug = get_log_level(args[1]) 
          when "--bypass-null", "-b" then 
              bypass_target_null = true
        end 
        args.shift
    end

    return terminate, dry_run, force_yes, run_mode, bypass_target_null, debug

  
end# }}}

def get_base() # {{{
#the bash script must output the var as 
#foo: value
#foo: value 
#..and the ruby script will parse that

    #_hostname = "";  #intentionally empty unless we need to be explicit.

    #TODO: move all this out , by using /usr/bin/env sh 
    #for the base_setup.sh to know/use the path etc .

    my_filename = $0
    #my_filename = __FILE__

    #UPDATE
    #CAUTION: linux 'dirname' allows a -z to append a NULL char and NOT a \n 
    #but no option in OpenBSD
    cmd_path = "dirname #{my_filename}" #zero is name of this perl script!
    debug( "cmd_path: '#{cmd_path}' " )

    runtime_path = %x(#{cmd_path})
    #puts "Result of dirname call (before line strip) : '#{runtime_path}' "

    #strip out \n 
    runtime_path = runtime_path.chomp 

    #-h $hostname 
    #above switch NOT used. unless needed in future. 
    #cmd = "#{runtime_path}/base_setup.sh"
    cmd = "base_setup.sh"
    debug( "Calling: base_setup.sh = #{cmd}")

    base_vars = %x( #{cmd} )
    debug( "base_vars : #{base_vars} ") 

    fields = {} # or Hash.new
    for line in base_vars.lines
        debug( "raw line : \"#{line.chomp}\" " )
        line =~ /^(.*?): (.*)$/ # Pre–colon text into $1, post–colon into $2
        debug( "$1 = '#{$1}' ")
        debug( "$2 = '#{$2}' ")
        fields[$1] = $2
    end
    
    debug( "variables from base_setup.sh...")

    fields.each do |key, value|
        debug( "\t#{key}:#{value}")
    end

    return fields 

end # }}}

def get_platform() # {{{
    #remember the -s switch to just get the OS name
    return %x{uname -a}
end# }}}

def setup_logfile_dir(logfile_dir)# {{{
    debug( "setup_logfile_dir:  logfile_dir: #{logfile_dir}")
    ##CAUTION: OpenBSD does NOT have '-v' args for mkdir !!!!
    cmd = "mkdir -p #{logfile_dir}" 
    debug( "command call: #{cmd} ")
    result = -1
    begin
        result = %x( #{cmd} )
        result = 0
    rescue 
        result = -2
        error "failure to run: " + cmd 
    end 
    debug( "mkdir result: #{result} ") 
    return result 
end# }}}

def clean_backup_dir(backup_dir)# {{{
#setup and clean out backup dir for next processing...
    debug( "clean_backup_dir: backup_dir: #{backup_dir}")

    if backup_dir.equal?("/") then 
        error "ERROR: backup_dir is root! Terminating now."
        return false
    end

    unless backup_dir.start_with?("/tmp") then 
        error "ERROR: backup_dir does not start with /tmp" 
        return false
    end 

    cmd = "rm -rf #{backup_dir} "
    debug "command call: #{cmd} "
    result = %x( #{cmd} )
    debug "clean_backup_dir: remove dir result : #{result}"

    #CAUTION: OpenBSD doesnt have -v args for mkdir
    cmd = "mkdir -p #{backup_dir} " 
    debug( "command call: #{cmd} " ) 
    result = %x( #{cmd} )
    debug( "clean_backup_dir: mkdir result : #{result}" )

    return true 
end# }}}

def file_data(level, type, user, group, mode, # {{{
                default_file_user = "" , 
                default_file_group ="", 
                default_file_mode ="" )
#looks silly, but incase need to add something to do a test etc, just keep as a sub
#originally a Perl construct. 
#TODO: there may be a better way of doing this is Ruby. 
# symbols or something? 
    h = Hash.new 
    h['level'] = level 
    h['type'] = type 
    h['user'] = user 
    h['group'] = group 
    h['mode'] = mode 
    h['default_file_mode'] = default_file_mode 
    h['default_file_user'] = default_file_user 
    h['default_file_group'] = default_file_group
    return h
end# }}}

def scan_source(path_dir)# {{{
#create hashtable for the filesystem structure to then do a acl/mode comparision against .
    debug ""
    debug "scan_source, starting for path <DIR> '" + path_dir + "'...", true
    result = scan_source_dir(path_dir, 0)
    if result < 0 then 
        error "scan_source_dir did not complete ok. Error: " + result.to_s
        return result 
    end

    result = show_prelim(false)
    if result < 0 then 
        error "show_prelim did not complete ok. Error: " + result.to_s
        return result
    end

    return 0

end# }}}

def get_parent_perms(key_path)# {{{
#this filepath does NOT exist in the XML Treepath, so do up a level and get the default values. 
    debug "\tkey_path: #{key_path}"

    last_dir_pos = key_path.rindex("/") 
    last_dir = key_path[0,last_dir_pos]
    debug "\tlast_dir: #{last_dir}"

    if $fileMap.key?(last_dir) == false then 
        error "ERROR: there is no key in the XML spec tree for '#{last_dir}'\n\tAdjust XML spec or similar"
        return false
    end

    file_data = $fileMap[last_dir] 

    h = Hash.new 
    #TODO recheck this .... 
    h['mode'] = file_data['default_file_mode'] 
    h['user'] = file_data['default_file_user'] 
    h['group'] = file_data['default_file_group']
    h['last_dir'] = last_dir 

    return h 

end# }}}

def get_mode(uri)# {{{
#do a file stat to get the Mode. 
#the perl chmod NEEDS an octal value input! 
#fyi: at THIS stage, it seems the result is bitmasked and output for the decimal output etc 
#but please note the octal printout format AND the bitwise mask 

    m = File.stat(uri).mode 

    #this returns 'good' value
    r1 = sprintf("%04o", m & 07777) #perls code too!

    #all these return same value 
    #puts "filemode oct: " + m.to_s(8)
    #r2 = sprintf("%04o", m) 
    #r3 = sprintf("%o", m) 

    #puts "filemode r2:  #{r2} " 
    #puts "filemode r3:  #{r3} " 
    #puts "filemode r1:  #{r1} " 

    return r1

end# }}}

def scan_source_dir(cur_dir, level)# {{{
#recusive scan into filesystem sourcedir to create hashmap of files and dirs
#to crossref with xml trees version 
    debug "" 
    debug("scan_source_dir call...")
    debug("\tsourcedir (GLOBAL): #{$sourcedir}" ) 
    debug("\tcur_dir: #{cur_dir}") 

    full_dir = $sourcedir + cur_dir
    debug("\tfull_dir (joined): #{full_dir}") 

    hash_key = cur_dir + "/" 
    debug "\tfileSourceMap <DIR> key insert : " + hash_key , true
    $fileSourceMap[ hash_key ] = file_data( level, 'd', '', '', get_mode(full_dir) ) 

    debug "\tEach file in Dir : '" + full_dir + "'..." 
    Dir.foreach(full_dir) { |file|
        #below . .. as not needed. 
        next if file == "." 
        next if file == ".." 

        debug ""
        debug("\t\t\tfile: #{file} ") 

        full_name = "#{full_dir}/#{file}"
        debug "\t\t\tfull_name: '" + full_name + "' "  
        if File.directory?(full_name) then 
            next_dir = cur_dir + "/" + file
            debug "\t\t\t\t<DIR>: next_dir: #{next_dir}" , true
            result = scan_source_dir(next_dir , level+1)
            if result < 0 then 
                error "\t\t\t\tscan_source_dir error! for dir: " + next_dir 
                return result
            end

        elsif File.file?(full_name) then 
            hash_key = "#{cur_dir}/#{file}"
            debug "\t\t\tfileSourceMap <FILE> insert, hash_key : '" + hash_key + "' ", true
            $fileSourceMap[hash_key] = file_data(level, 'f', '', '', get_mode(full_name)) 
        else
            error "\t\t\tscanning filesystem: entry not a dir or file!"
            return -1 
        end 
    }

    return 0 
end
# }}}

def scan_tree_simple( # {{{
        prev_path, 
        obj_cur_dir, 
        level, 
        parent_default_file_user="", 
        parent_default_file_group="", 
        parent_default_file_mode="") 
#take in a parsed HASH obj using the gem xmlsimple  
#navigate its Hash tree and map over to the original source structure 

    #walk thru array[] of Hash items for the <directory> xml element...
    #i think only ONE hash item it seems with either dir/file entries 
    info ""
    info "scan_tree_simple Starting..."
    info "\tprev_path: " + prev_path , true
    info "\tlevel: " + level.to_s
    info "\tparent_default_file_mode: " + parent_default_file_mode 
    info "\tparent_default_file_user: " + parent_default_file_user
    info "\tparent_default_file_group: " + parent_default_file_group

    unless obj_cur_dir.is_a?(Array) then 
        error ("\tinput dir for scanning NOT an array!\t level: #{level}")
        return false
    end

    for h in obj_cur_dir 

        unless h.is_a?(Hash) then 
            error( "\titem inside directory array NOT a hash! class type: #{ h.class}  ")
            return false 
        end

        cur_path = h['name'] 
        info "\tcur_path: #{cur_path}", true

        #either it's own settings or go to the parents value . so it trickles down ...  
        default_file_mode = h['default_file_mode'] ||= parent_default_file_mode
        default_file_user = h[ 'default_file_user' ] ||= parent_default_file_user
        default_file_group = h['default_file_group'] ||= parent_default_file_group

        info( "\tdefault_file_mode = #{default_file_mode}")
        info( "\tdefault_file_user = #{default_file_user}")
        info( "\tdefault_file_group  = #{default_file_group}")

        joined_path = prev_path + cur_path + "/" 
        debug("\tnew joined_path: " + joined_path ) 
        $fileMap[joined_path] = file_data( level, "d", h['user'], h['group'] , h['mode'] , 
                                default_file_user, default_file_group, default_file_mode)
        debug "fileMap key insert <DIR> '" + joined_path + "'", true
        #the list of files ONLY. directories have their OWN array...
        if h.has_key?('file') then 
            file_list = h['file'] 
            for f in file_list 
                unless f.is_a?(Hash) then 
                    error( "\titem inside file array NOT a hash! class type: #{f.class}  ")
                    return false 
                end
                
                hash_key = joined_path + f[ "name" ] 
                info "\tfileMap key insert <FILE> '" + hash_key + "' " , true
                $fileMap[hash_key] = file_data( level, 'f' , f[ 'user' ] , f[ 'group' ] , f[ 'mode' ] ,
                                         default_file_user , default_file_group , default_file_mode )
            end
        end

        if h.has_key?('directory') then 
            next_child_dirs = h['directory'] 
            info "\trecursing into next dir..."
            result = scan_tree_simple(joined_path, next_child_dirs, level+1, default_file_user, default_file_group, default_file_mode)
            unless result 
                error("scan_tree_simple returned false, under : " + joined_path)
                return false
            end 
        end

    end 

    return true

end # }}}

def empty_or_nil?(p)# {{{
    if p.nil? then 
       return true 
    end 
    #TODO: assumes empty prop; test for Int/num etc 
    if p.empty? then 
        return true
    end

    return false
end# }}}

def simple_copy(path_dir="", delete=false, user=nil, group=nil, mode=0 )# {{{
    #simple rsync version just for default-website for e.g , no xml tree etc 
    #and signular file transfer 
   
    source = $sourcedir + path_dir
    debug "simple_copy: source: '#{ source }' ", true

    target = $TEST_PREFIX + path_dir 
    debug "simple_copy: target: '#{target}' " , true

    if File.exist?(source) == false then 
        error( "\tsimple_copy: Terminating: '#{ source }' does not exist!")
        return false 
    end 

    rsync_chmod=""
    if Dir.exist?(source) then 
        # Add the slash to start copying the contents that follows the end dir and NOT the dir itself
        #TODO test for trailing slash already there...
        source += "/"
        #CAUTION: OpenBSD does not do -v on mkdir!!
        mkdir = "mkdir -p #{target}"
        debug("\tcommand call: '#{mkdir}'") 
        res = %x( #{mkdir} )
        debug( "\tsimple_copy: mkdir -p #{target}  result: '#{res}' ")
    else 
      #its a file, so use the mode param to set the rsync value. 
      if mode > 0 then
        #TODO: test for if valid number
        rsync_chmod=" --chmod=F" + mode.to_s
      end
    end 

    logfile_part = path_dir
    logfile_part = logfile_part.gsub(/\// , "_") 

    rsync_dryrun = _get_dry_run() ? " --dry-run" : "" 
    if empty_or_nil?(user) || empty_or_nil?(group) then 
        user ||= ""
        group ||= ""
        debug "warning!!! user or group nil/empty" 
        debug "\t user: " + user.to_s 
        debug "\t group: " + group.to_s
    end 
    rsync_chown = ( empty_or_nil?(user) || empty_or_nil?(group) ) ? "" : " --chown #{user}:#{group}"
    #TODO: caution , as of Tue 06 Dec 2022 08:13:42, using the '/etc/ dir in the mapcopy! 
    # being allowed to cascade delete from there is very dangerous! 
    rsync_delete = delete ? " --delete" : "" 
    rsync_backup = " --backup --backup-dir=#{$backupdir}#{path_dir}"
    rsync_logfile = " --log-file=#{$logfiledir}/#{ logfile_part }_#{ Time.now.to_i }.log"
    rsync_switches = "#{rsync_dryrun} -v -a --human-readable#{rsync_delete}#{rsync_chown}#{rsync_chmod}#{rsync_backup}#{rsync_logfile}"
    rsync_call = "rsync#{rsync_switches} #{source} #{target} "
    
    debug( "rsync call to be run: '#{rsync_call}' ")
    result = %x( #{rsync_call} )
    debug "simple_copy: rsync result: #{result} "
    return true

end# }}}

def get_webowner() # {{{
    webowner = "" #website structure user/group 
    case get_platform() 
        when /Alpine/
            webowner = "apache" 
        when /OpenBSD/
            webowner = "www"
        else 
            webowner = "http"
    end 
    return webowner 
end # }}}

def map_copy(path_dir, delete) # {{{
# open a xml tree spec to get mode/user/group etc 
# recurse into all directory elements to get all file elements etc 
# populate the hash tree with the full file path for easy lookup 
#pass over to copysourcefiles with delete param for rsync to decide if to rm extra files NOT in source dir.  

    unless Dir.exist?(path_dir) 
        return false
    end

    #TODO: turn into params , 
    #TODO  CHECK IF RUST CODE OR OTHER IS NOT AFFECTED BY --NOT-- CURRENTLY FLUSHING THESE TWO VARS!
    $fileMap.clear 
    $fileSourceMap.clear
    puts ""
    info "Starting map_copy: '" + path_dir + "'" , true
    info "\tclearing both hash maps : fileMap and fileSourceMap" 

    
    #NOTE: Ruby does NOT do nice find/replace regex all in one line like Perl5 
    #Example: file_part =~ s/[\/\.]/\_/g  was the original Perl call 

    #replace / . with _ chars 
    #the path will also have "." as is /logrotate.d/
    file_part = path_dir
    file_part = file_part.gsub(/[\/\.]/ ,"_") 
    debug "\tfile_part: '#{file_part}' " 

    file_name = "#{$configdir}/tree_definitions/spec#{file_part}.xml"
    puts "XML Spec Tree: '#{file_name}' "

#     test = { 
#         "test"=>"ss",
#         "dir" => [ 
#             {"at"=>"1" , "po"=>"2"},
#             {"at"=>"1" , "po"=>"2"}
#         ]
#     }
# 
#     puts "TEST" 
#     puts test 
#     foo = test['dir'] 
#     puts "foo isa: #{ foo.class }" 
#     puts "FOO" 
#     puts foo 
# 
    unless File.exist?(file_name) 
        error "\tFile spec '#{file_name}' not found."
        return false
    end

    tree_spec = XmlSimple.xml_in(file_name)
    unless tree_spec.class == Hash 
        error "\txml-simple did not return a hashmap!" 
        return false
    end

    #puts tree_spec 
    #puts tree_spec['directory']
    #puts "TREE dir #{t.class} "
    #return false

    #Toplevel must only be ONE 'directory' key ...unless XmlSimple changes. 
    result = scan_tree_simple("", tree_spec['directory'] , 0 )
    unless result 
        error("\tRoot scan_tree_simple returned false for " + file_name)  
        return false
    end

    

    #puts "=========DUMP========="
    #puts $fileMap; 

    #now scan source file dir created hashtable. 
    #recusrse into real build directory and cross-ref the mode/user/group from the hashtable. 
    
    result = scan_source(path_dir) 
    if result < 0 then 
        error "\tnon-ok termination! Err no: " + result.to_s
        return false
    end

    result = copy_source_files(path_dir, delete)
    unless result 
        error "\tfailed result from copy_source_files: '" + path_dir + "' "
        return false 
    end 


    #puts "-----dump source files--------- " 
    #puts $fileSourceMap 


    return true 

end# }}}

def copy_source_files(path_dir, delete = false)# {{{
#re-chmods the files/dirs that are in the preset TMP dir --NOT the target files 
#re-chowns the '' '' ''
#THEN rsync that dir structure across.

 
    debug("")
    debug("copy_source_files::Copying fileSourceMap data...") 

    debug "fileSourceMap files..."
    for k,v in $fileSourceMap 

        source_file = $sourcedir + k
        info("source_file: " + source_file) 

        p = sprintf("Copying: '%s' \n\t(L:%d) key:'%s' (%s) user:%s group:%s  mode:%s\n", 
            source_file, 
            v['level'],
            k,
            v['type'],
            v['user'],
            v['group'],
            v['mode'] )
              
        debug(p) 

        #CAUTION!!! chmod NEEDS OCTAL value! not string, or decimal!!!
        #r1 = sprintf("%04o", m & 07777) #perls code
        #o_mode = sprintf("%o",  m ).to_i(8) & 07777
        #o_mode = sprintf("%d",  m ).to_i(10)

        m = v['mode']
        o_mode = sprintf("%o",  m ).to_i(8) 

        debug( "mode (str) : " + m )
        debug( "mode (oct): #{o_mode} ")

        result = File.chmod(o_mode, source_file) 
        if result != 1 then 
            error( "File: #{source_file} did not chmod" )
            result false 
        end 

        g = v['group'] 
        u = v['user'] 
        debug "user: " + u 
        debug "group: " + g

    
        group_info = Etc.getgrnam(g)
        gid = group_info.gid 

        user_info = Etc.getpwnam(u)
        uid = user_info.uid 

        debug "user: '" + u + "' uid= " + uid.to_s 
        debug "group: '" + g + "' gid= " + gid.to_s 

        result=0
        begin
            result = File.chown( uid, gid , source_file) 
        rescue
            error "result is:" + result.to_s
            error( "File: #{source_file} did not chown." )
        end 
        
        if result != 1 then 
            error( "File result !=1 : #{source_file} did not chown." )
            return false 
        end 


    end

    logfile_part = path_dir
    logfile_part = logfile_part.gsub(/\//, "_") #replace / with _ char. 

    rsync_dryrun = _get_dry_run() ? "--dry-run " : ""
    rsync_switches ="#{rsync_dryrun}-a --human-readable --verbose"
    rsync_backup = " --backup --backup-dir=#{$backupdir}#{path_dir}"
    rsync_logfile = " --log-file=#{$logfiledir}/#{logfile_part}_#{ Time.now.to_i }.log"
    rsync_delete = delete ? " --delete" : ""
    
    #prefix normally /home/foo/Downloads/perl_test to safeguard against overcopy.
    target_dir = $TEST_PREFIX + path_dir
    debug("target_dir: " + target_dir)
    
    #CAUTION: OpenBSD does not do -v for mkdir 
    mkdir_target = "mkdir -p #{target_dir}"
    debug "mkdir call '#{mkdir_target}'" 
    res = %x( #{mkdir_target} ) 
    debug( "result mkdir target: '#{res}' ")
    
    #IMPORTANT! use the trailing  '/' at end of rsync source to avoid starting at the dir, ..so to get contents of the dir.
    #TODO: Rust's version FAILS when extra blank space chars are between args. Dbl check here. 
    # ...rsync main.c (1492) err or something. 
    rsync_call = "rsync #{rsync_switches}#{rsync_delete}#{rsync_backup}#{rsync_logfile} #{$sourcedir}#{path_dir}/ #{target_dir}"
    debug( "calling: #{rsync_call}")

    res = %x( #{rsync_call} )
    debug( "rsync result : '#{res}' " )
    #TODO parse the stdout response!!!
    # this assumes it ran okay!

    return true 

end #func# }}}

def show_prelim(this_is_re_show = false) # {{{
#show to user What will happen re file Mode, Missing etc   
#iterate the xmltree first then the filesys source tree 

    puts ""
    puts "====================== XML Tree spec map =============================="
    puts "??? = File missing from XML spec master file."
    puts "======================================================================="
    puts ""

    for key,item in $fileMap
       alert = $fileSourceMap.has_key?(key) ? "   " : "???" 
       printf("%s %s %s:%s %s L%d %s\n" ,
               alert,
               (item['type'] ||= '?').upcase,
               item['user'] ||= "NULL",
               item['group'] ||= "NULL", 
               item['mode'] ||= "NULL", 
               item['level'] , 
               key, 
        )
    end 

    puts "" 
    puts "===================== Filesystem source map ==========================="
    puts "??? = File not listed in XML Tree spec. "
    puts "XXX = File's mode will be overridden to match the XML file's version. "
    puts "      <<OVERRIDE>>  OLD --> NEW "
    puts "======================================================================="
    puts "" 
 
    for key, item in $fileSourceMap 
        msg = ""
        alert = "   "

        if $fileMap.has_key?(key) then 
             #it exists in the XML treemap...
             #the fileSourceMap CANNOT really have the target user/group as it is coming from a dev machine anyway. 
             $fileSourceMap[ key ]['user'] = $fileMap[ key ]['user']
             $fileSourceMap[ key ]['group'] = $fileMap[ key ]['group']

            if $fileMap[ key ]['mode'] != item['mode'] then
                alert = "XXX"
                msg = "<<OVERRIDE>> #{item['mode']} --> #{$fileMap[ key ]['mode']} "
                #RESET value to match the XML spec.
                $fileSourceMap[ key ]['mode'] = $fileMap[ key ]['mode']
            end
            
        else 
            #missing file: 
            #the file in the sourcemap is NOT in the XML tree spec. 
            #get last dir / go up a dir and get the default perms for that file. 
            perms = get_parent_perms(key)
            unless perms
                error "Failed to get parent permissions for '" + key + "' "
                return -3
            end 
            alert="???"
            msg="**Missing** (owner dir: #{perms['last_dir'] } )"
            $fileSourceMap[ key ]['user'] = perms['user']
            $fileSourceMap[ key ]['group'] = perms['group']
            $fileSourceMap[ key ]['mode'] = perms['mode']
        end 

       printf("%s %s %s:%s %s L%d %s %s\n" ,
               alert,
               item['type'].to_s.upcase, 
               item['user'] ||= "NULL",
               item['group'] ||= "NULL", 
               item['mode'] ||= "NULL", 
               item['level'] , 
               key, 
               msg
        )

    end #endfor

    debug "tree spec count:  #{$fileMap.count} "
    debug "file source count: #{$fileSourceMap.count} "

    if _get_force_yes() then
        puts "FORCING a Yes for all would-be user input!"
    else
        puts "Considering all above, proceed with the file copy tasks? y/N"
        answer = gets 
        answer  = answer.gsub(/\n/ , "") 
        debug "STDIN: answer:  '#{answer}' " 
        if answer.upcase == 'Y' then
            
              unless this_is_re_show then 
                  result = show_prelim(true)
                  if result < 0 then 
                      return result
                  end
              end
            puts "Answered 'Yes', Now Processing..."

        elsif answer.upcase == 'N' || answer == "" then
            puts "Answers 'No' -Bailing out of the map_copy!"
            return -1
        else 
            error "Could not understand response. Terminating now. "
            return -2
        end
    end

    return 0

end# }}}


def set_globals() 
#store the common variables from common shell script
    recs = get_base()
    debug("set_globals: recs type: " + recs.class.to_s) 
    unless recs.is_a?(Hash) 
        error "get_base did not return a HashMap!" 
        return -1
    end
    if recs.empty then 
        error "get_base() did not return any records!" 
        return -2
    end if 
    if (err = recs['ERROR']) != nil then 
        error "Terminal error for base_setup: " + err 
        return -3
    end 

    null="NULL"

    $configdir = recs[ 'configdir' ] ||= null
    $swapdir = recs[ 'swapdir' ] ||= null
    $target = recs[ 'target' ] ||= null
    $buildname = recs[ 'buildname' ] ||= null
    $builddir = recs[ 'build_dir' ] ||= null
    $sourcedir = $builddir

    $backupdir = "#{$swapdir}/base_backup_BUILD_#{$target}"
    $logfiledir = "#{$swapdir}/rsync_log"

    debug("$sourcedir = #{$sourcedir}" )

    #just ignore the NULL suffix, as a Dev machine was most likely matched 
    target_null_test = _get_bypass_target_null() ? "" : null
        
    if [ target_null_test, "" ].any?{|i| i == $target } then 
        error( "target is NULL or empty.\n\tTerminating process\n\tProbably running on the bare metal dev machine. this is a no-no. ")
        return -4
    end

#recursive added map of each file and dir
#xml treespec version
    $fileMap = {} 

#recursive added map of each file and dir 
#filesystem version
    $fileSourceMap = {}

    debug( "ARG: debug (log level): #$debug" )
    debug( "ARG: run_mode = #{$run_mode}" )
    debug( "ARG: force_yes = #{$force_yes}")
    debug( "ARG: dry_run = #{$dry_run}" )
    debug( "ARG: bypass_target_null = #{$bypass_target_null}" )
    debug( "TEST_PREFIX:  '#{$TEST_PREFIX}' " )

    if $dry_run then 
        puts "Running in DRY-RUN mode for rsync, no changes saved!!!"
    end

    return 0

end 

def get_command_lines(full_csv_path) 

    unless File.exist?(full_csv_path) 
        error "command file missing!\n\tpath: " + full_csv_path
        return false
    end

    lines = [] 

    File.open(full_csv_path, "r") { |file|
        while file.eof? == false do 
            x = file.readline
            # find any hashcomment starting a line OR any blank line 
            unless x =~ /\s*#.*|^\s*$/
                 lines.push(x)
            end
        end 
    }

    if lines.empty? then 
      error "all empty command lines!"
      return false
    end 

    return lines

#     for x in lines 
#         puts "line::" + x
#     end
# 
end 

def lookup_user(p)
  #todo Etc call
  return p
end

def lookup_group(p)
  #todo Etc call
  return p
end

def parse_path(p)
  p = p.strip 
  if p == "/" then 
    error "path is root!" 
    return false
  end 

  #TODO regex for url/path
  return p # or false
end

def parse_bool(p) 
   p = p.strip
   unless p == "true" || p == "false" 
     return false
   end
   return p.to_s  #return the STRING
end

def convert_bool(p)
  return  p == "true" ? true : false
end

def parse_user(p) 
  
  p = p.strip 
  if empty_or_nil?(p) then 
    return false
  end

  if p == "<webowner>" then
    p = get_webowner()
  end

  if false == p = lookup_user(p) then 
    return false
  end

  return p 

end

def parse_group(p) 
  p = p.strip #TODO <--error for nil type!!!
  if empty_or_nil?(p) then 
    return false
  end
  if p == "<webowner>" then
    p = get_webowner()
  end
  if false == p = lookup_group(p) then 
    return false
  end
  return p 
end

def parse_mode(p) 

  if p.nil? then 
    return 0 
  end
  p = p.to_s 
  p = p.strip  

  if p.empty? then 
    return 0
  end
  r = p.to_i #manage the zero case down stream...
  return r
end

def parse_simple_cmd(cmd)
#attempt simple_copy parse 

#s,"/var/www/html/sites/default", false, <webowner>, <webowner>, mode
#remember! the first element was SHIFTed , so s is gone!

  debug "cmd: " + cmd.to_s

  if cmd.size < 4 then 
    return nil, "array size less than 4"
  end 
  pos_path=0
  pos_delete=1
  pos_user=2
  pos_group=3
  pos_mode=4

  if false == param_path = parse_path(cmd[pos_path] ||= "") then 
    return nil, "position #{pos_path.to_s} is not a valid path." 
  end

  if false == param_delete = parse_bool(cmd[pos_delete] ||= "") then 
    return nil, "position #{pos_delete.to_s} is not valid a bool"  
  else
    param_delete = convert_bool(param_delete) #convert after guard,
  end

  if false == param_user = parse_user(cmd[pos_user]) then 
    return nil, "position #{pos_user.to_s} is not a valid user" 
  end

  if false == param_group = parse_group(cmd[pos_group]) then 
    return nil, "position #{pos_group} is not a group"
  end
  
  if false == param_mode = parse_mode(cmd[pos_mode]) then 
    return nil, "position #{pos_mode} is not a mode"
  end

  command = { 
    "type" => "simple", 
    "path" => param_path, 
    "delete" => param_delete, 
    "user" => param_user, 
    "group" => param_group, 
    "mode" => param_mode
  }

  return command, false

end 

def parse_mapcopy_cmd(cmd)

# m,"/etc/httpd/conf" , false
# remember - the first element SHOULD of been shifted!

  if cmd.size < 2 then 
    return nil, "array size less than 2"
  end 

  pos_path=0
  pos_delete=1

  if false == param_path = parse_path(cmd[pos_path] ||= "") then 
    return nil, "position #{pos_path} is an invalid path." 
  end

  if false == param_delete = parse_bool(cmd[pos_delete] ||= "") then 
    return nil, "position #{pos_delete} is not a bool"
  else
    param_delete = convert_bool(param_delete) #convert after guard,
  end

 
  command = { 
    "type" => "mapcopy", 
    "path" => param_path, 
    "delete" => param_delete, 
  }

  return command, false

end

def parse_command(cmd)

  action = cmd.shift
  action = action.strip
  
  unless action == "s" || action  == "m"
    return false
  end

  command = false
  err = false

  if action == "s" then 
    command, err = parse_simple_cmd(cmd)
  elsif action == "m" then 
    command, err = parse_mapcopy_cmd(cmd)
  else 
    err = "unknown option" 
  end 

  return command, err

end 


def create_command_list(config_dir, command_csv_file)
#push good parsed commands to the array 

  full_path = config_dir + "/" + command_csv_file 
  lines = get_command_lines(full_path) 
  unless lines 
    error "get_command_lines failed!" 
    return nil, false
  end 

  debug "command lines: " + lines.to_s

  delim = ","
  command_list = Array.new

  for x in lines
      command, err = parse_command( x.split(delim) )
      if err then 
        error "failed to parse command!"
        error "\t" + err.to_s
        return nil, false
      end 
      command_list.push(command)  
  end

  return command_list, nil

end 

def process_commands(command_list)

  unless command_list.is_a?(Array) 
    error "command_list not an Array!"
    return -1
  end 

  if command_list.size == 0 then 
    error "command_list size zero!"
    return -1
  end 

  for c in command_list 

    result = false

    if c['type'] == "simple" then 
      debug "COMMAND:: path: " +  c['path'] 
      debug "COMMAND:: " + c.to_s 
      result = simple_copy(c['path'], c['delete'], c['user'] , c['group'], c['mode'] ) 

    elsif c['type'] == "mapcopy" then 
      debug "COMMAND:: path: " + c['path'] 
      debug "COMMAND:: " + c.to_s
      result = map_copy(c['path'], c['delete']) 
    end

    unless result 
      error "call failure with simple_copy or map_copy command!" 
      return false
    end 

  end #endfor

  info "processed commands okay!", true
  return true
end 


def _get_dry_run() 
  return $dry_run
end 

def _get_debug() 
  return $debug
end 

def _get_force_yes()
  return $force_yes
end

def _get_bypass_target_null()
  return $bypass_target_null
end


def debug_params(terminate, dry_run, force_yes, run_mode, bypass_target_null, debug)
#failsafe debug values 
  puts "Arguments: "
  puts "\tterminate=" + terminate.to_s
  puts "\tdry_run = " + dry_run.to_s 
  puts "\tforce_yes = " + force_yes.to_s
  puts "\trun_mode = " + run_mode
  puts "\tbypass_target_null = " + bypass_target_null.to_s 
  puts "\tdebug = " + debug.to_s
end 

###############################################################################
#                           Logic Start...
###############################################################################

$VERSION = "0.1.1"

#Hardcoded value to prefix the target destination for testing
#SET TO "" for the LIVE/REAL scenario testing
#$TEST_PREFIX = '/home/troy/Downloads/ruby_test_mapcopy'
$TEST_PREFIX = ''

mapcopy_csv_file="mapcopy_commands.csv"

terminate, $dry_run, $force_yes, $run_mode, $bypass_target_null, $debug = set_args() 
#use just incase...
#debug_params(terminate, $dry_run, $force_yes, $run_mode, $bypass_target_null, $debug)
if terminate 
    #use at bash/sh, echo $? to show the result
    info "terminating process (set_args)"
    exit 1
end
splash($VERSION)
unless 0 == result = set_globals() then 
    error "set_globals() failure" 
    exit 2
end


###########TODO
#testing the reshuffle of global vars. 
#remove once confident. 

unless clean_backup_dir($backupdir)
    error "clean_backup_dir() call failure" 
    exit 3
end 

unless 0 == x = setup_logfile_dir($logfiledir) 
    error "setup_logfile_dir() call failure" 
    exit 4
end 

webowner = get_webowner()
debug("webowner: #{webowner}") 


command_list, err = create_command_list($configdir, mapcopy_csv_file) 
unless err == nil 
  error "create_command_list failed!" 
  exit 5
end 

#TODO Need to decide if another ARGV is needed to proceed-on-error 
# or terminate of the first/any error and ignore the outstanding items in list.

unless true == result = process_commands(command_list)
  error "process_commands failed!"
  exit 6
end 

puts "program finished."
exit 0 #zero is unix success. 
__END__

#################### now obselete.......
# all these should be in the CSV file!
# keep for posterity / reference.
# simple_copy("/var/www/html/sites/default", false, webowner, webowner )  
# simple_copy("/var/www/html/sites/default_http" , false, webowner, webowner )  
# simple_copy("/var/www/html/sites/default_https" , false, webowner, webowner )  
# 
# map_copy("/etc/httpd/conf" , false )  
# map_copy("/etc/apache2" , false )  
# map_copy("/etc/postfix" , false )  
# map_copy("/etc/postgresql" , false )  
# map_copy("/etc/php" , false )  
# map_copy("/etc/php8" , false )  
# map_copy("/var/lib/postgres" , false )  
# map_copy("/var/lib/postgresql" , false )  
# map_copy("/root", false )  
# map_copy("/home/vagrant", false )  
# map_copy("/home/arch", false )  
# map_copy("/home/alpine", false )  
# map_copy("/etc/logrotate.d" , false )  
# 
# simple_copy("/etc/redis.conf" , false, 'redis', 'redis' )  
# simple_copy("/etc/ssl_self" , false, 'root', 'wheel' )  
# simple_copy("/etc/letsencrypt" , false, 'root', 'wheel' )  
# ##################################################################


#goodbye. 



